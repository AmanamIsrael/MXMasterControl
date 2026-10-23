import CoreGraphics
import Foundation
import MXMasterCore
import OSLog

/// Carries all the values the poster needs to build and emit the Dock-swipe events.
struct DesktopSwipeGestureEvent: Equatable, Sendable {
  let phase: Int64
  let progress: Double
  let lastDelta: Double
}

protocol DesktopSwipeEventPosting: Sendable {
  func post(_ event: DesktopSwipeGestureEvent)
}

/// Posts the phased Dock gesture that macOS uses for interactive Space transitions.
/// The undocumented event encoding is isolated in the poster so the HID interpretation and the
/// rest of the action dispatcher stay independent of this OS-specific boundary.
final class DesktopSwipeSynthesizer: @unchecked Sendable {
  private let poster: DesktopSwipeEventPosting
  private let progressScale: @Sendable () -> Double

  private let lock = NSLock()
  private var progress = 0.0
  private var lastDelta = 0.0
  private var pointsToProgress = 0.0

  init(
    poster: DesktopSwipeEventPosting = CGEventDockSwipePoster(),
    progressScale: @escaping @Sendable () -> Double = DesktopSwipeSynthesizer.progressScaleAtPointer
  ) {
    self.poster = poster
    self.progressScale = progressScale
  }

  func post(_ update: DesktopSwipeUpdate) {
    lock.lock()
    defer { lock.unlock() }

    switch update.phase {
    case .began:
      pointsToProgress = progressScale()
      let delta = Double(update.deltaX) * pointsToProgress
      progress = delta
      lastDelta = delta
      poster.post(.init(phase: 1, progress: progress, lastDelta: lastDelta))
    case .changed:
      guard pointsToProgress > 0 else { return }
      let delta = Double(update.deltaX) * pointsToProgress
      guard delta != 0 else { return }
      progress += delta
      lastDelta = delta
      poster.post(.init(phase: 2, progress: progress, lastDelta: lastDelta))
    case .ended:
      guard pointsToProgress > 0 else { return }
      let phase: Int64 = progress == 0 || lastDelta.sign == progress.sign ? 4 : 8
      poster.post(.init(phase: phase, progress: progress, lastDelta: lastDelta))
      reset()
    case .cancelled:
      guard pointsToProgress > 0 else { return }
      poster.post(.init(phase: 8, progress: progress, lastDelta: lastDelta))
      reset()
    }
  }

  private func reset() {
    progress = 0
    lastDelta = 0
    pointsToProgress = 0
  }

  static func progressScaleAtPointer() -> Double {
    let point = CGEvent(source: nil)?.location ?? .zero
    var display = CGMainDisplayID()
    var count: UInt32 = 0
    if CGGetDisplaysWithPoint(point, 1, &display, &count) != .success || count == 0 {
      display = CGMainDisplayID()
    }
    let width = max(CGDisplayBounds(display).width, 1)
    return 2.0 / (width + 63.0)
  }
}

/// Builds the undocumented Dock-swipe events and posts them. The encoding changed in macOS 27,
/// so each OS generation has its own encoder. Both encoders resolve their private symbols once,
/// at construction time.
final class CGEventDockSwipePoster: DesktopSwipeEventPosting, @unchecked Sendable {
  private static let logger = Logger(
    subsystem: "com.amanamisrael.MXMasterControl",
    category: "desktop-swipe"
  )

  private let encoder: (any DockSwipeEncoding)?

  init() {
    if #available(macOS 27, *) {
      encoder = HIDEventDockSwipeEncoder()
    } else {
      encoder = LegacyFieldsDockSwipeEncoder()
    }
  }

  func post(_ event: DesktopSwipeGestureEvent) {
    guard let encoder else {
      Self.logger.error("Private Dock-swipe API unavailable on this macOS version; desktop swipe disabled")
      return
    }
    guard let events = encoder.events(for: event) else {
      Self.logger.error("Could not create desktop swipe events")
      return
    }

    for cgEvent in events {
      cgEvent.post(tap: .cgSessionEventTap)
    }
    if event.phase != 2 {
      Self.logger.debug(
        "Posted desktop swipe phase=\(event.phase, privacy: .public) progress=\(event.progress, privacy: .public)"
      )
    }
  }
}

private protocol DockSwipeEncoding: Sendable {
  /// The events to post, in order.
  func events(for event: DesktopSwipeGestureEvent) -> [CGEvent]?
}

extension DesktopSwipeGestureEvent {
  /// Ended (4) and cancelled (8) events carry an exit speed. `* 100` approximates real trackpad values.
  fileprivate var exitSpeed: Double? {
    phase == 4 || phase == 8 ? lastDelta * 100 : nil
  }
}

/// macOS 27 and later. WindowServer ignores the legacy CGEvent fields and reads an IOHIDEvent
/// attached to the Dock-control event (type 30). An event without one is dropped, and
/// WindowServer logs "Failed to extract HID event from indirect gesture SLSEventRecord".
/// The IOKit and SkyLight functions are private, so they are looked up at runtime.
private struct HIDEventDockSwipeEncoder: DockSwipeEncoding {
  private typealias Create = @convention(c) (CFAllocator?, UInt32, UInt64, UInt32) -> Unmanaged<
    CFTypeRef
  >?
  private typealias SetInteger = @convention(c) (CFTypeRef, UInt32, Int) -> Void
  private typealias SetFloat = @convention(c) (CFTypeRef, UInt32, Double) -> Void
  private typealias Append = @convention(c) (CFTypeRef, CFTypeRef, UInt32) -> Void
  private typealias Attach = @convention(c) (CGEvent, CFTypeRef) -> Void

  // IOHIDEventType values, and fields encoded as (type << 16) | index.
  private static let dockSwipeType: UInt32 = 23
  private static let velocityType: UInt32 = 9
  private static let dockSwipeMotion = dockSwipeType << 16 | 1
  private static let dockSwipeProgress = dockSwipeType << 16 | 2
  private static let dockSwipeFlavor = dockSwipeType << 16 | 5
  private static let velocityX = velocityType << 16 | 0
  private static let velocityY = velocityType << 16 | 1
  private static let velocityZ = velocityType << 16 | 2
  private static let horizontalMotion = 1
  private static let dockPrimaryFlavor = 3
  /// The gesture phase lives in the event options (kIOHIDEventEventOptionPhaseShift).
  private static let phaseShift: UInt32 = 24
  private static let dockControlEventType: UInt32 = 30

  private let create: Create
  private let setInteger: SetInteger
  private let setFloat: SetFloat
  private let append: Append
  private let attach: Attach

  init?() {
    guard
      let iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW),
      let skyLight = dlopen(
        "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW),
      let create = dlsym(iokit, "IOHIDEventCreate"),
      let setInteger = dlsym(iokit, "IOHIDEventSetIntegerValue"),
      let setFloat = dlsym(iokit, "IOHIDEventSetFloatValue"),
      let append = dlsym(iokit, "IOHIDEventAppendEvent"),
      let attach = dlsym(skyLight, "SLEventSetIOHIDEvent")
    else { return nil }

    self.create = unsafeBitCast(create, to: Create.self)
    self.setInteger = unsafeBitCast(setInteger, to: SetInteger.self)
    self.setFloat = unsafeBitCast(setFloat, to: SetFloat.self)
    self.append = unsafeBitCast(append, to: Append.self)
    self.attach = unsafeBitCast(attach, to: Attach.self)
  }

  func events(for event: DesktopSwipeGestureEvent) -> [CGEvent]? {
    let timestamp = mach_absolute_time()
    guard
      let hidEvent = create(
        nil, Self.dockSwipeType, timestamp, UInt32(event.phase) << Self.phaseShift
      )?.takeRetainedValue(),
      let eventType = CGEventType(rawValue: Self.dockControlEventType),
      let dockEvent = CGEvent(source: nil)
    else { return nil }

    setInteger(hidEvent, Self.dockSwipeMotion, Self.horizontalMotion)
    setInteger(hidEvent, Self.dockSwipeFlavor, Self.dockPrimaryFlavor)
    // The HID payload runs opposite to the legacy fields: negating keeps the Space moving with
    // the hand. Progress is stored as 16.16 fixed point, so values below ~0.00002 round to zero.
    setFloat(hidEvent, Self.dockSwipeProgress, -event.progress)

    if let exitSpeed = event.exitSpeed {
      guard
        let velocity = create(nil, Self.velocityType, timestamp, 0)?.takeRetainedValue()
      else { return nil }
      setFloat(velocity, Self.velocityX, -exitSpeed)
      setFloat(velocity, Self.velocityY, -exitSpeed)
      setFloat(velocity, Self.velocityZ, 0)
      append(hidEvent, velocity, 0)
    }

    dockEvent.type = eventType
    attach(dockEvent, hidEvent)
    return [dockEvent]
  }
}

/// macOS 15 through 26. A gesture event (type 29) paired with a Dock-control event (type 30),
/// with the swipe encoded in private CGEvent fields.
private struct LegacyFieldsDockSwipeEncoder: DockSwipeEncoding {
  private let f55: CGEventField
  private let f41: CGEventField
  private let f110: CGEventField
  private let f132: CGEventField
  private let f134: CGEventField
  private let f124: CGEventField
  private let f135: CGEventField
  private let f119: CGEventField
  private let f139: CGEventField
  private let f123: CGEventField
  private let f165: CGEventField
  private let f136: CGEventField
  private let f129: CGEventField?
  private let f130: CGEventField?

  init?() {
    func field(_ rawValue: UInt32) -> CGEventField? { CGEventField(rawValue: rawValue) }
    guard
      let f55 = field(55), let f41 = field(41),
      let f110 = field(110), let f132 = field(132),
      let f134 = field(134), let f124 = field(124),
      let f135 = field(135), let f119 = field(119),
      let f139 = field(139), let f123 = field(123),
      let f165 = field(165), let f136 = field(136)
    else { return nil }

    self.f55 = f55
    self.f41 = f41
    self.f110 = f110
    self.f132 = f132
    self.f134 = f134
    self.f124 = f124
    self.f135 = f135
    self.f119 = f119
    self.f139 = f139
    self.f123 = f123
    self.f165 = f165
    self.f136 = f136
    f129 = field(129)
    f130 = field(130)
  }

  func events(for event: DesktopSwipeGestureEvent) -> [CGEvent]? {
    guard let gestureEvent = CGEvent(source: nil), let dockEvent = CGEvent(source: nil) else {
      return nil
    }

    let phase = event.phase
    let progress = event.progress

    gestureEvent.setDoubleValueField(f55, value: 29)
    gestureEvent.setDoubleValueField(f41, value: 33_231)

    dockEvent.setDoubleValueField(f55, value: 30)
    dockEvent.setDoubleValueField(f110, value: 23)
    dockEvent.setIntegerValueField(f132, value: phase)
    dockEvent.setIntegerValueField(f134, value: phase)
    dockEvent.setDoubleValueField(f124, value: progress)

    let progressBits = Int64(UInt64(Float(progress).bitPattern))
    dockEvent.setIntegerValueField(f135, value: progressBits)
    dockEvent.setDoubleValueField(f41, value: 33_231)

    let horizontalSentinel = Double(Float.leastNonzeroMagnitude)
    dockEvent.setDoubleValueField(f119, value: horizontalSentinel)
    dockEvent.setDoubleValueField(f139, value: horizontalSentinel)
    dockEvent.setDoubleValueField(f123, value: 1)
    dockEvent.setDoubleValueField(f165, value: 1)
    dockEvent.setIntegerValueField(f136, value: 0)

    if let exitSpeed = event.exitSpeed, let f129, let f130 {
      dockEvent.setDoubleValueField(f129, value: exitSpeed)
      dockEvent.setDoubleValueField(f130, value: exitSpeed)
    }

    return [dockEvent, gestureEvent]
  }
}
