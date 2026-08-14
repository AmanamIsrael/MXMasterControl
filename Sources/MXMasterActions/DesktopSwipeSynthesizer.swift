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

    // These fields mirror the WindowServer's Dock-swipe event representation on macOS 15–26.
    gestureEvent.setDoubleValueField(Self.field(55), value: 29)
    gestureEvent.setDoubleValueField(Self.field(41), value: 33_231)

    dockEvent.setDoubleValueField(Self.field(55), value: 30)
    dockEvent.setDoubleValueField(Self.field(110), value: 23)
    dockEvent.setIntegerValueField(Self.field(132), value: phase)
    dockEvent.setIntegerValueField(Self.field(134), value: phase)
    dockEvent.setDoubleValueField(Self.field(124), value: progress)

    let progressBits = Int64(UInt64(Float(progress).bitPattern))
    dockEvent.setIntegerValueField(Self.field(135), value: progressBits)
    dockEvent.setDoubleValueField(Self.field(41), value: 33_231)

    // Horizontal Dock swipe (1), encoded both as a float-bit sentinel and an integer field.
    let horizontalSentinel = Double(Float.leastNonzeroMagnitude)
    dockEvent.setDoubleValueField(Self.field(119), value: horizontalSentinel)
    dockEvent.setDoubleValueField(Self.field(139), value: horizontalSentinel)
    dockEvent.setDoubleValueField(Self.field(123), value: 1)
    dockEvent.setDoubleValueField(Self.field(165), value: 1)
    dockEvent.setIntegerValueField(Self.field(136), value: 0)

    if phase == 4 || phase == 8 {
      let exitSpeed = lastDelta * 100
      dockEvent.setDoubleValueField(Self.field(129), value: exitSpeed)
      dockEvent.setDoubleValueField(Self.field(130), value: exitSpeed)
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

  private static func field(_ rawValue: UInt32) -> CGEventField {
    // The private Dock fields are outside the public enum but accepted by CoreGraphics.
    CGEventField(rawValue: rawValue)!
  }
}
