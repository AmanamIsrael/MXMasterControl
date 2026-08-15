import CoreGraphics
import Foundation
import MXMasterCore
import OSLog

/// Carries all the values the poster needs to build and emit the CGEvent pair.
struct DesktopSwipeGestureEvent: Equatable, Sendable {
  let phase: Int64
  let progress: Double
  let lastDelta: Double
}

protocol DesktopSwipeEventPosting: Sendable {
  func post(_ event: DesktopSwipeGestureEvent)
}

/// Posts the phased Dock gesture that macOS uses for interactive Space transitions.
/// The undocumented event fields are isolated in the poster so the HID interpretation and the
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

/// Resolves the private CGEventField IDs once at construction time and builds
/// the undocumented Dock-swipe event pair on every `post(_:)`.
final class CGEventDockSwipePoster: DesktopSwipeEventPosting, @unchecked Sendable {
  private static let logger = Logger(
    subsystem: "com.amanamisrael.MXMasterControl",
    category: "desktop-swipe"
  )

  private struct ResolvedFields {
    let f55: CGEventField
    let f41: CGEventField
    let f110: CGEventField
    let f132: CGEventField
    let f134: CGEventField
    let f124: CGEventField
    let f135: CGEventField
    let f119: CGEventField
    let f139: CGEventField
    let f123: CGEventField
    let f165: CGEventField
    let f136: CGEventField
    let f129: CGEventField?
    let f130: CGEventField?
  }

  private let fields: ResolvedFields?

  init() {
    fields = Self.resolveFields()
  }

  func post(_ event: DesktopSwipeGestureEvent) {
    guard let fields else {
      Self.logger.error("Private CGEvent fields unavailable on this macOS version; desktop swipe disabled")
      return
    }

    guard let gestureEvent = CGEvent(source: nil), let dockEvent = CGEvent(source: nil) else {
      Self.logger.error("Could not create desktop swipe events")
      return
    }

    let phase = event.phase
    let progress = event.progress

    gestureEvent.setDoubleValueField(fields.f55, value: 29)
    gestureEvent.setDoubleValueField(fields.f41, value: 33_231)

    dockEvent.setDoubleValueField(fields.f55, value: 30)
    dockEvent.setDoubleValueField(fields.f110, value: 23)
    dockEvent.setIntegerValueField(fields.f132, value: phase)
    dockEvent.setIntegerValueField(fields.f134, value: phase)
    dockEvent.setDoubleValueField(fields.f124, value: progress)

    let progressBits = Int64(UInt64(Float(progress).bitPattern))
    dockEvent.setIntegerValueField(fields.f135, value: progressBits)
    dockEvent.setDoubleValueField(fields.f41, value: 33_231)

    let horizontalSentinel = Double(Float.leastNonzeroMagnitude)
    dockEvent.setDoubleValueField(fields.f119, value: horizontalSentinel)
    dockEvent.setDoubleValueField(fields.f139, value: horizontalSentinel)
    dockEvent.setDoubleValueField(fields.f123, value: 1)
    dockEvent.setDoubleValueField(fields.f165, value: 1)
    dockEvent.setIntegerValueField(fields.f136, value: 0)

    if phase == 4 || phase == 8 {
      let exitSpeed = event.lastDelta * 100
      if let f129 = fields.f129, let f130 = fields.f130 {
        dockEvent.setDoubleValueField(f129, value: exitSpeed)
        dockEvent.setDoubleValueField(f130, value: exitSpeed)
      }
    }

    dockEvent.post(tap: .cgSessionEventTap)
    gestureEvent.post(tap: .cgSessionEventTap)
    if phase != 2 {
      Self.logger.debug(
        "Posted desktop swipe phase=\(phase, privacy: .public) progress=\(progress, privacy: .public)"
      )
    }
  }

  private static func resolveFields() -> ResolvedFields? {
    guard
      let f55 = field(55), let f41 = field(41),
      let f110 = field(110), let f132 = field(132),
      let f134 = field(134), let f124 = field(124),
      let f135 = field(135), let f119 = field(119),
      let f139 = field(139), let f123 = field(123),
      let f165 = field(165), let f136 = field(136)
    else { return nil }

    return ResolvedFields(
      f55: f55, f41: f41, f110: f110, f132: f132, f134: f134,
      f124: f124, f135: f135, f119: f119, f139: f139,
      f123: f123, f165: f165, f136: f136,
      f129: field(129), f130: field(130)
    )
  }

  private static func field(_ rawValue: UInt32) -> CGEventField? {
    CGEventField(rawValue: rawValue)
  }
}
