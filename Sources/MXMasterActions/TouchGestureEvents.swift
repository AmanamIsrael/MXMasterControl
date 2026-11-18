import CoreGraphics

/// Trackpad gestures without raw touches: the gesture events AppKit turns into
/// `swipe(with:)`, `magnify(with:)` and `smartMagnify(with:)`. The event type and fields are
/// not in the public headers; Mac Mouse Fix, SensibleSideButtons and Calftrail's
/// TouchSynthesis use the same encoding.
enum TouchGestureEvents {
  private static let gestureType = CGEventType(rawValue: 29)
  private static let hidEventTypeField = CGEventField(rawValue: 110)
  private static let magnificationField = CGEventField(rawValue: 113)
  private static let swipeDirectionField = CGEventField(rawValue: 115)
  private static let phaseField = CGEventField(rawValue: 132)

  /// `IOHIDEventType` values.
  private enum HIDEventType: Int64 {
    case zoom = 8
    case navigationSwipe = 16
    case zoomToggle = 22
  }

  /// `IOHIDEventPhaseBits` values.
  enum Phase: Int64 {
    case began = 1
    case changed = 2
    case ended = 4
  }

  /// The trackpad's page swipe.
  static func postPageSwipe(_ direction: NavigationPoster.Direction) {
    pageSwipeEvents(direction).forEach { $0.post(tap: .cgSessionEventTap) }
  }

  /// One step of a pinch.
  static func post(_ frame: PinchMotion.Frame) {
    magnificationEvent(frame)?.post(tap: .cgSessionEventTap)
  }

  /// A two-finger double tap: zooms to the item under the pointer, or back out.
  static func postSmartZoom() {
    smartZoomEvent()?.post(tap: .cgSessionEventTap)
  }

  /// A page swipe begins with a direction and ends without one.
  static func pageSwipeEvents(_ direction: NavigationPoster.Direction) -> [CGEvent] {
    guard
      let began = gestureEvent(.navigationSwipe), let ended = gestureEvent(.navigationSwipe),
      let phaseField, let swipeDirectionField
    else { return [] }
    // IOHIDSwipeMask: left goes back, right goes forward.
    began.setIntegerValueField(phaseField, value: Phase.began.rawValue)
    began.setIntegerValueField(swipeDirectionField, value: direction == .back ? 4 : 8)
    ended.setIntegerValueField(phaseField, value: Phase.ended.rawValue)
    return [began, ended]
  }

  static func magnificationEvent(_ frame: PinchMotion.Frame) -> CGEvent? {
    guard let event = gestureEvent(.zoom), let magnificationField, let phaseField else {
      return nil
    }
    event.setIntegerValueField(phaseField, value: phase(frame.phase).rawValue)
    event.setDoubleValueField(magnificationField, value: frame.magnification)
    return event
  }

  static func smartZoomEvent() -> CGEvent? { gestureEvent(.zoomToggle) }

  static func phase(_ phase: PinchMotion.Phase) -> Phase {
    switch phase {
    case .began: .began
    case .changed: .changed
    case .ended: .ended
    }
  }

  private static func gestureEvent(_ type: HIDEventType) -> CGEvent? {
    guard let gestureType, let hidEventTypeField, let event = CGEvent(source: nil) else {
      return nil
    }
    event.type = gestureType
    event.setIntegerValueField(hidEventTypeField, value: type.rawValue)
    return event
  }
}
