import CoreGraphics
import Foundation
import MXMasterCore
import OSLog

/// Posts the phased Dock gesture that macOS uses for interactive Space transitions.
/// The undocumented event fields are isolated here so the HID interpretation and the
/// rest of the action dispatcher stay independent of this OS-specific boundary.
final class DesktopSwipeSynthesizer: @unchecked Sendable {
  private static let logger = Logger(
    subsystem: "com.amanamisrael.MXMasterControl",
    category: "desktop-swipe"
  )

  private let lock = NSLock()
  private var progress = 0.0
  private var lastDelta = 0.0
  private var pointsToProgress = 0.0

  func post(_ update: DesktopSwipeUpdate) {
    lock.lock()
    defer { lock.unlock() }

    switch update.phase {
    case .began:
      pointsToProgress = Self.progressScaleAtPointer()
      let delta = Double(update.deltaX) * pointsToProgress
      progress = delta
      lastDelta = delta
      postDockSwipe(phase: 1)
    case .changed:
      guard pointsToProgress > 0 else { return }
      let delta = Double(update.deltaX) * pointsToProgress
      guard delta != 0 else { return }
      progress += delta
      lastDelta = delta
      postDockSwipe(phase: 2)
    case .ended:
      guard pointsToProgress > 0 else { return }
      let phase: Int64 = progress == 0 || lastDelta.sign == progress.sign ? 4 : 8
      postDockSwipe(phase: phase)
      reset()
    case .cancelled:
      guard pointsToProgress > 0 else { return }
      postDockSwipe(phase: 8)
      reset()
    }
  }

  private func postDockSwipe(phase: Int64) {
    guard let gestureEvent = CGEvent(source: nil), let dockEvent = CGEvent(source: nil) else {
      Self.logger.error("Could not create desktop swipe events")
      return
    }

    guard
      let f55 = Self.field(55), let f41 = Self.field(41),
      let f110 = Self.field(110), let f132 = Self.field(132),
      let f134 = Self.field(134), let f124 = Self.field(124),
      let f135 = Self.field(135), let f119 = Self.field(119),
      let f139 = Self.field(139), let f123 = Self.field(123),
      let f165 = Self.field(165), let f136 = Self.field(136)
    else {
      Self.logger.error("Private CGEvent fields unavailable on this macOS version; desktop swipe disabled")
      return
    }

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

    if phase == 4 || phase == 8 {
      let exitSpeed = lastDelta * 100
      if let f129 = Self.field(129), let f130 = Self.field(130) {
        dockEvent.setDoubleValueField(f129, value: exitSpeed)
        dockEvent.setDoubleValueField(f130, value: exitSpeed)
      }
    }

    dockEvent.post(tap: .cgSessionEventTap)
    gestureEvent.post(tap: .cgSessionEventTap)
    if phase != 2 {
      Self.logger.debug(
        "Posted desktop swipe phase=\(phase, privacy: .public) progress=\(self.progress, privacy: .public)"
      )
    }
  }

  private func reset() {
    progress = 0
    lastDelta = 0
    pointsToProgress = 0
  }

  private static func progressScaleAtPointer() -> Double {
    let point = CGEvent(source: nil)?.location ?? .zero
    var display = CGMainDisplayID()
    var count: UInt32 = 0
    if CGGetDisplaysWithPoint(point, 1, &display, &count) != .success || count == 0 {
      display = CGMainDisplayID()
    }
    let width = max(CGDisplayBounds(display).width, 1)
    return 2.0 / (width + 63.0)
  }

  private static func field(_ rawValue: UInt32) -> CGEventField? {
    CGEventField(rawValue: rawValue)
  }
}
