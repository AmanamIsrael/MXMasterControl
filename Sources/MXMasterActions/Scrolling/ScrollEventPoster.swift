import CoreGraphics

/// Builds the continuous scroll events a trackpad sends: pixel deltas with a gesture or
/// momentum phase. Apps read the phases to rubber-band at edges and to tell a gesture from
/// its momentum.
enum ScrollEventPoster {
  /// Marks events this app posts, so its own event tap lets them through.
  static let marker: Int64 = 0x4D58_5343  // "MXSC"

  /// Not in the public headers: whether natural scrolling flipped the event's direction.
  private static let invertedFromDeviceField = CGEventField(rawValue: 137)

  static func post(_ frame: ScrollMotion.Frame, invertedFromDevice: Bool) {
    event(frame, invertedFromDevice: invertedFromDevice)?.post(tap: .cgSessionEventTap)
  }

  static func event(_ frame: ScrollMotion.Frame, invertedFromDevice: Bool) -> CGEvent? {
    guard
      let event = CGEvent(
        scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
        wheel1: frame.dy, wheel2: frame.dx, wheel3: 0)
    else { return nil }
    event.setIntegerValueField(.eventSourceUserData, value: marker)
    event.setIntegerValueField(.scrollWheelEventScrollPhase, value: scrollPhase(frame.gesture))
    event.setIntegerValueField(
      .scrollWheelEventMomentumPhase, value: momentumPhase(frame.momentum))
    if let invertedFromDeviceField {
      event.setIntegerValueField(invertedFromDeviceField, value: invertedFromDevice ? 1 : 0)
    }
    return event
  }

  static func isInvertedFromDevice(_ event: CGEvent) -> Bool {
    guard let invertedFromDeviceField else { return false }
    return event.getIntegerValueField(invertedFromDeviceField) != 0
  }

  static func scrollPhase(_ phase: ScrollMotion.GesturePhase?) -> Int64 {
    switch phase {
    case nil: 0
    case .began: Int64(CGScrollPhase.began.rawValue)
    case .changed: Int64(CGScrollPhase.changed.rawValue)
    case .ended: Int64(CGScrollPhase.ended.rawValue)
    }
  }

  static func momentumPhase(_ phase: ScrollMotion.MomentumPhase?) -> Int64 {
    switch phase {
    case nil: Int64(CGMomentumScrollPhase.none.rawValue)
    case .began: Int64(CGMomentumScrollPhase.begin.rawValue)
    case .changed: Int64(CGMomentumScrollPhase.continuous.rawValue)
    case .ended: Int64(CGMomentumScrollPhase.end.rawValue)
    }
  }
}
