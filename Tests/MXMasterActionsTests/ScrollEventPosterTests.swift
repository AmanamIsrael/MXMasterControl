import AppKit
import Testing

@testable import MXMasterActions

// AppKit decodes each posted frame as a trackpad scroll: precise deltas with the phase that
// scroll views use to rubber-band and to tell a gesture from its momentum.

@Test func gestureFramesArriveAsPreciseTrackpadScrolls() throws {
  let frame = ScrollMotion.Frame(dx: 0, dy: -12, gesture: .began, momentum: nil)
  let cgEvent = try #require(ScrollEventPoster.event(frame, invertedFromDevice: false))
  let event = try #require(NSEvent(cgEvent: cgEvent))
  #expect(event.type == .scrollWheel)
  #expect(event.hasPreciseScrollingDeltas)
  #expect(event.scrollingDeltaY == -12)
  #expect(event.phase == .began)
  #expect(event.momentumPhase == [])
  #expect(!event.isDirectionInvertedFromDevice)
}

@Test func momentumFramesArriveWithTheirMomentumPhase() throws {
  let frame = ScrollMotion.Frame(dx: 7, dy: 0, gesture: nil, momentum: .changed)
  let cgEvent = try #require(ScrollEventPoster.event(frame, invertedFromDevice: true))
  let event = try #require(NSEvent(cgEvent: cgEvent))
  #expect(event.scrollingDeltaX == 7)
  #expect(event.phase == [])
  #expect(event.momentumPhase == .changed)
  #expect(event.isDirectionInvertedFromDevice)
}
