import AppKit
import Testing

@testable import MXMasterActions

// AppKit decodes each synthesized event into the NSEvent a trackpad produces, so apps handle
// it in magnify(with:), smartMagnify(with:) and swipe(with:).

@Test func pinchFramesArriveAsMagnifyEventsWithTheirPhase() throws {
  let expected: [(PinchMotion.Phase, Double, NSEvent.Phase)] = [
    (.began, 0, .began), (.changed, 0.125, .changed), (.ended, 0, .ended),
  ]
  for (phase, magnification, appKitPhase) in expected {
    let cgEvent = try #require(
      TouchGestureEvents.magnificationEvent(
        PinchMotion.Frame(magnification: magnification, phase: phase)))
    let event = try #require(NSEvent(cgEvent: cgEvent))
    #expect(event.type == .magnify)
    #expect(event.phase == appKitPhase)
    #expect(Double(event.magnification) == magnification)
  }
}

@Test func smartZoomArrivesAsSmartMagnify() throws {
  let cgEvent = try #require(TouchGestureEvents.smartZoomEvent())
  #expect(NSEvent(cgEvent: cgEvent)?.type == .smartMagnify)
}

@Test func pageSwipeArrivesAsASwipeTowardItsDirection() throws {
  for (direction, deltaX): (NavigationPoster.Direction, CGFloat) in [(.back, 1), (.forward, -1)] {
    let events = TouchGestureEvents.pageSwipeEvents(direction).compactMap(NSEvent.init(cgEvent:))
    #expect(events.map(\.type) == [.swipe, .swipe])
    #expect(events.map(\.phase) == [.began, .ended])
    #expect(events.first?.deltaX == deltaX)
  }
}
