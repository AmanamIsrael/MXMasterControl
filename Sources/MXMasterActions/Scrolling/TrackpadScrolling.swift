import AppKit
import CoreGraphics
import Foundation
import OSLog

/// Makes the mouse wheel behave like a trackpad.
///
/// An event tap swallows wheel ticks and replays them as trackpad events. With smooth
/// scrolling, `ScrollMotion` turns them into continuous, phased scrolling with momentum, for
/// both the main wheel and the thumb wheel. With pinch zoom, Command-scroll becomes the
/// magnification gesture of a pinch through `PinchMotion`. Trackpads and the Magic Mouse
/// already send continuous events, so they pass through untouched, as do scrolls with Control
/// or Option held. The tap, the frame timer and all motion state live on one dedicated thread,
/// so a busy main thread cannot stall scrolling. If the app quits or crashes, macOS removes
/// the tap and the wheel works natively again.
public final class TrackpadScrolling: @unchecked Sendable {
  public struct Features: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) { self.rawValue = rawValue }

    /// Smooth, phased scrolling with momentum.
    public static let smoothScrolling = Features(rawValue: 1 << 0)
    /// Command-scroll zooms like a pinch.
    public static let pinchZoom = Features(rawValue: 1 << 1)
  }

  /// What a wheel event turns into.
  enum WheelRoute: Equatable {
    case scroll(ScrollMotion.Vector)
    /// Points the wheel turned away from the user, whatever the macOS scroll direction.
    case zoom(Double)
  }

  /// A pinch grows the content by about 10% for each notch of a slow wheel turn.
  static let magnificationPerPoint = 0.01

  private static let logger = Logger(
    subsystem: "com.amanamisrael.MXMasterControl",
    category: "scrolling"
  )

  private let thread = RunLoopThread(name: "MXMasterControl.scrolling")
  private let lock = NSLock()
  private var tap: CFMachPort?
  private var tapSource: CFRunLoopSource?
  private var features: Features = []

  // Touched only on `thread`.
  private var motion = ScrollMotion()
  private var pinch = PinchMotion()
  private var frameTimer: CFRunLoopTimer?
  private var invertedFromDevice = false
  private var frameInterval: CFTimeInterval = 1.0 / 60

  public init() {}

  deinit { _ = removeTap() }

  /// Turns on exactly `features`; with none, the tap is removed and the wheel works natively.
  /// Returns false when macOS refuses the event tap, which happens until the app has
  /// Accessibility access.
  @discardableResult
  public func apply(_ features: Features) -> Bool {
    guard !features.isEmpty else {
      stop()
      return true
    }
    guard installTap() else { return false }
    lock.lock()
    self.features = features
    lock.unlock()
    // A motion in progress for a feature just turned off ends at once.
    thread.perform { [weak self] in
      guard let self else { return }
      if !features.contains(.smoothScrolling) { post(motion.interrupt()) }
      if !features.contains(.pinchZoom) { post(pinch.interrupt()) }
    }
    return true
  }

  private func installTap() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard tap == nil else { return true }

    let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
    guard
      let newTap = CGEvent.tapCreate(
        tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
        eventsOfInterest: mask, callback: trackpadScrollingTapCallback,
        userInfo: Unmanaged.passUnretained(self).toOpaque())
    else {
      Self.logger.error("Scroll event tap refused; Accessibility is likely missing")
      return false
    }
    // Built-in displays report a refresh rate of 0 through Core Graphics; NSScreen knows
    // ProMotion's 120 Hz. Read once here, on the caller's thread.
    let framesPerSecond = Double(NSScreen.main?.maximumFramesPerSecond ?? 60)
    let interval = 1 / min(max(framesPerSecond, 60), 120)
    thread.perform { [weak self] in self?.frameInterval = interval }
    let source = CFMachPortCreateRunLoopSource(nil, newTap, 0)
    let runLoop = thread.runLoop
    CFRunLoopAddSource(runLoop, source, .commonModes)
    CGEvent.tapEnable(tap: newTap, enable: true)
    CFRunLoopWakeUp(runLoop)
    tap = newTap
    tapSource = source
    Self.logger.info("Trackpad-style scrolling started")
    return true
  }

  /// Removes the tap. A scroll or pinch in progress ends before this returns, so apps never
  /// stay inside a gesture, even when the app quits right after.
  public func stop() {
    guard removeTap() else { return }
    let ended = DispatchSemaphore(value: 0)
    thread.perform { [weak self] in
      defer { ended.signal() }
      guard let self else { return }
      post(motion.interrupt())
      post(pinch.interrupt())
      stopFrameTimer()
    }
    ended.wait()
    Self.logger.info("Trackpad-style scrolling stopped")
  }

  private func removeTap() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard let oldTap = tap else { return false }
    CGEvent.tapEnable(tap: oldTap, enable: false)
    if let tapSource { CFRunLoopRemoveSource(thread.runLoop, tapSource, .commonModes) }
    CFMachPortInvalidate(oldTap)
    tap = nil
    tapSource = nil
    features = []
    return true
  }

  /// Runs on `thread` for each event the tap sees.
  fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
      lock.lock()
      if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
      lock.unlock()
      return Unmanaged.passUnretained(event)
    case .scrollWheel:
      break
    default:
      return Unmanaged.passUnretained(event)
    }

    lock.lock()
    let features = features
    lock.unlock()
    let isInverted = ScrollEventPoster.isInvertedFromDevice(event)
    guard
      event.getIntegerValueField(.eventSourceUserData) != ScrollEventPoster.marker,
      event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0,
      let route = Self.route(
        vertical: event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1),
        horizontal: event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2),
        flags: event.flags, invertedFromDevice: isInverted, features: features)
    else { return Unmanaged.passUnretained(event) }

    let now = ProcessInfo.processInfo.systemUptime
    // A trackpad never scrolls and pinches at once, so one ends the other.
    switch route {
    case .scroll(let delta):
      post(pinch.interrupt())
      invertedFromDevice = isInverted
      post(motion.tick(delta, at: now))
    case .zoom(let points):
      post(motion.interrupt())
      post(pinch.tick(points * Self.magnificationPerPoint, at: now))
    }
    startFrameTimer()
    return nil
  }

  /// Where a wheel event goes, or `nil` when it should pass through. Command-scroll zooms
  /// with the main wheel; turning the wheel away from you zooms in, as on most platforms.
  static func route(
    vertical: Int64, horizontal: Int64, flags: CGEventFlags, invertedFromDevice: Bool,
    features: Features
  ) -> WheelRoute? {
    if features.contains(.pinchZoom), flags.contains(.maskCommand),
      flags.isDisjoint(with: [.maskControl, .maskAlternate]), vertical != 0
    {
      return .zoom(Double(invertedFromDevice ? -vertical : vertical))
    }
    guard features.contains(.smoothScrolling) else { return nil }
    return wheelDelta(vertical: vertical, horizontal: horizontal, flags: flags).map(WheelRoute.scroll)
  }

  /// The thumb wheel scrolls sideways (axis 2). Shift turns the main wheel sideways too:
  /// AppKit does that for line-based wheel events, but not for the continuous events posted
  /// here, so the swap happens before smoothing. Other modifiers keep their native meaning.
  static func wheelDelta(vertical: Int64, horizontal: Int64, flags: CGEventFlags)
    -> ScrollMotion.Vector?
  {
    guard flags.isDisjoint(with: [.maskControl, .maskAlternate, .maskCommand]) else { return nil }
    var delta = ScrollMotion.Vector(x: Double(horizontal), y: Double(vertical))
    if flags.contains(.maskShift), horizontal == 0 {
      delta = ScrollMotion.Vector(x: Double(vertical), y: 0)
    }
    return delta == .zero ? nil : delta
  }

  private func post(_ frames: [ScrollMotion.Frame]) {
    for frame in frames {
      ScrollEventPoster.post(frame, invertedFromDevice: invertedFromDevice)
    }
  }

  private func post(_ frames: [PinchMotion.Frame]) {
    frames.forEach(TouchGestureEvents.post)
  }

  private func startFrameTimer() {
    guard frameTimer == nil else { return }
    let interval = frameInterval
    let timer = CFRunLoopTimerCreateWithHandler(
      nil, CFAbsoluteTimeGetCurrent() + interval, interval, 0, 0
    ) { [weak self] _ in
      self?.advanceFrame()
    }
    CFRunLoopAddTimer(thread.runLoop, timer, .commonModes)
    frameTimer = timer
  }

  private func advanceFrame() {
    let now = ProcessInfo.processInfo.systemUptime
    post(motion.advance(to: now))
    post(pinch.advance(to: now))
    if !motion.isMoving, !pinch.isMoving { stopFrameTimer() }
  }

  private func stopFrameTimer() {
    guard let frameTimer else { return }
    CFRunLoopTimerInvalidate(frameTimer)
    self.frameTimer = nil
  }
}

private func trackpadScrollingTapCallback(
  proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
  guard let userInfo else { return Unmanaged.passUnretained(event) }
  let scrolling = Unmanaged<TrackpadScrolling>.fromOpaque(userInfo).takeUnretainedValue()
  return scrolling.handle(type, event)
}

/// A thread that keeps a run loop alive for event taps and timers.
final class RunLoopThread: @unchecked Sendable {
  let runLoop: CFRunLoop

  init(name: String) {
    let ready = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var loop: CFRunLoop?
    let thread = Thread {
      loop = CFRunLoopGetCurrent()
      // A run loop with no sources returns at once; this one keeps it waiting.
      var context = CFRunLoopSourceContext()
      CFRunLoopAddSource(loop, CFRunLoopSourceCreate(nil, 0, &context), .defaultMode)
      ready.signal()
      CFRunLoopRun()
    }
    thread.name = name
    thread.qualityOfService = .userInteractive
    thread.start()
    ready.wait()
    runLoop = loop!
  }

  func perform(_ block: @escaping () -> Void) {
    CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue, block)
    CFRunLoopWakeUp(runLoop)
  }
}
