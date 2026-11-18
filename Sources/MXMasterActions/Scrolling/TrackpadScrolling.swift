import AppKit
import CoreGraphics
import Foundation
import OSLog

/// Makes mouse-wheel scrolling behave like a trackpad: smooth, phased, with momentum.
///
/// An event tap swallows wheel ticks and `ScrollMotion` replays them as continuous scroll
/// events. Trackpads and the Magic Mouse already send continuous events, so they pass through
/// untouched, as do scrolls with a modifier key held. The tap, the frame timer and all motion
/// state live on one dedicated thread, so a busy main thread cannot stall scrolling. If the
/// app quits or crashes, macOS removes the tap and the wheel scrolls natively again.
public final class TrackpadScrolling: @unchecked Sendable {
  private static let logger = Logger(
    subsystem: "com.amanamisrael.MXMasterControl",
    category: "scrolling"
  )

  private let thread = RunLoopThread(name: "MXMasterControl.scrolling")
  private let lock = NSLock()
  private var tap: CFMachPort?
  private var tapSource: CFRunLoopSource?

  // Touched only on `thread`.
  private var motion = ScrollMotion()
  private var frameTimer: CFRunLoopTimer?
  private var invertedFromDevice = false
  private var frameInterval: CFTimeInterval = 1.0 / 60

  public init() {}

  deinit { _ = removeTap() }

  public var isRunning: Bool {
    lock.lock()
    defer { lock.unlock() }
    return tap != nil
  }

  /// Starts smoothing wheel scrolling. Returns false when macOS refuses the event tap, which
  /// happens until the app has Accessibility access.
  @discardableResult
  public func start() -> Bool {
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

  /// Stops smoothing. A scroll in progress ends at once, so apps never stay inside a gesture.
  public func stop() {
    guard removeTap() else { return }
    thread.perform { [weak self] in
      guard let self else { return }
      post(motion.interrupt())
      stopFrameTimer()
    }
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

    guard let delta = Self.wheelDelta(of: event) else {
      return Unmanaged.passUnretained(event)
    }
    invertedFromDevice = ScrollEventPoster.isInvertedFromDevice(event)
    post(motion.tick(delta, at: ProcessInfo.processInfo.systemUptime))
    startFrameTimer()
    return nil
  }

  /// The wheel movement to smooth, or `nil` for events that should pass through.
  static func wheelDelta(of event: CGEvent) -> ScrollMotion.Vector? {
    guard
      event.getIntegerValueField(.eventSourceUserData) != ScrollEventPoster.marker,
      event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0,
      event.flags.isDisjoint(with: [.maskShift, .maskControl, .maskAlternate, .maskCommand]),
      event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2) == 0
    else { return nil }
    let dy = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
    guard dy != 0 else { return nil }
    return ScrollMotion.Vector(x: 0, y: Double(dy))
  }

  private func post(_ frames: [ScrollMotion.Frame]) {
    for frame in frames {
      ScrollEventPoster.post(frame, invertedFromDevice: invertedFromDevice)
    }
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
    post(motion.advance(to: ProcessInfo.processInfo.systemUptime))
    if !motion.isMoving { stopFrameTimer() }
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
