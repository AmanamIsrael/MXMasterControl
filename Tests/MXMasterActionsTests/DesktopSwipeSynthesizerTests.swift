import Foundation
import MXMasterCore
import Testing

@testable import MXMasterActions

private final class RecordingPoster: DesktopSwipeEventPosting, @unchecked Sendable {
  private let lock = NSLock()
  private var recorded: [DesktopSwipeGestureEvent] = []

  func post(_ event: DesktopSwipeGestureEvent) {
    lock.lock()
    recorded.append(event)
    lock.unlock()
  }

  var events: [DesktopSwipeGestureEvent] {
    lock.lock()
    defer { lock.unlock() }
    return recorded
  }
}

private func synthesizer(
  poster: RecordingPoster,
  scale: Double = 0.001,
  endRepeatDelays: [Duration] = []
) -> DesktopSwipeSynthesizer {
  DesktopSwipeSynthesizer(
    poster: poster, progressScale: { _ in scale }, endRepeatDelays: endRepeatDelays)
}

@Test func swipeBeganPostsPhaseOneWithScaledProgress() {
  let poster = RecordingPoster()
  let sut = synthesizer(poster: poster, scale: 0.001)

  sut.post(DesktopSwipeUpdate(phase: .began, axis: .horizontal, delta: 500))

  #expect(poster.events == [
    DesktopSwipeGestureEvent(axis: .horizontal, phase: 1, progress: 0.5, lastDelta: 0.5),
  ])
}

@Test func swipeChangedAccumulatesProgressAndPostsPhaseTwo() {
  let poster = RecordingPoster()
  let sut = synthesizer(poster: poster, scale: 0.001)

  sut.post(DesktopSwipeUpdate(phase: .began, axis: .horizontal, delta: 500))
  sut.post(DesktopSwipeUpdate(phase: .changed, axis: .horizontal, delta: 300))
  sut.post(DesktopSwipeUpdate(phase: .changed, axis: .horizontal, delta: 200))

  #expect(poster.events.count == 3)
  #expect(poster.events[1] == DesktopSwipeGestureEvent(axis: .horizontal, phase: 2, progress: 0.8, lastDelta: 0.3))
  #expect(poster.events[2] == DesktopSwipeGestureEvent(axis: .horizontal, phase: 2, progress: 1.0, lastDelta: 0.2))
}

@Test func swipeChangedWithZeroDeltaIsIgnored() {
  let poster = RecordingPoster()
  let sut = synthesizer(poster: poster)

  sut.post(DesktopSwipeUpdate(phase: .began, axis: .horizontal, delta: 500))
  sut.post(DesktopSwipeUpdate(phase: .changed, axis: .horizontal, delta: 0))

  #expect(poster.events.count == 1)
}

@Test func swipeChangedBeforeBeganIsIgnored() {
  let poster = RecordingPoster()
  let sut = synthesizer(poster: poster)

  sut.post(DesktopSwipeUpdate(phase: .changed, axis: .horizontal, delta: 100))

  #expect(poster.events.isEmpty)
}

@Test func swipeEndedCommitsWhenDirectionMatchesProgress() {
  let poster = RecordingPoster()
  let sut = synthesizer(poster: poster, scale: 0.001)

  sut.post(DesktopSwipeUpdate(phase: .began, axis: .horizontal, delta: 500))
  sut.post(DesktopSwipeUpdate(phase: .changed, axis: .horizontal, delta: 300))
  sut.post(DesktopSwipeUpdate(phase: .ended, axis: .horizontal, delta: 0))

  #expect(poster.events.last?.phase == 4)
  #expect(poster.events.last?.progress ?? -1 == 0.8)
}

@Test func swipeEndedCancelsWhenDirectionOpposesProgress() {
  let poster = RecordingPoster()
  let sut = synthesizer(poster: poster, scale: 0.001)

  sut.post(DesktopSwipeUpdate(phase: .began, axis: .horizontal, delta: 500))
  sut.post(DesktopSwipeUpdate(phase: .changed, axis: .horizontal, delta: -200))
  sut.post(DesktopSwipeUpdate(phase: .ended, axis: .horizontal, delta: 0))

  #expect(poster.events.last?.phase == 8)
}

@Test func swipeEndedCommitsWhenProgressIsZero() {
  let poster = RecordingPoster()
  let sut = synthesizer(poster: poster, scale: 0.001)

  sut.post(DesktopSwipeUpdate(phase: .began, axis: .horizontal, delta: 0))
  sut.post(DesktopSwipeUpdate(phase: .ended, axis: .horizontal, delta: 0))

  #expect(poster.events.last?.phase == 4)
}

@Test func swipeCancelledPostsPhaseEight() {
  let poster = RecordingPoster()
  let sut = synthesizer(poster: poster, scale: 0.001)

  sut.post(DesktopSwipeUpdate(phase: .began, axis: .horizontal, delta: 500))
  sut.post(DesktopSwipeUpdate(phase: .changed, axis: .horizontal, delta: 300))
  sut.post(DesktopSwipeUpdate(phase: .cancelled, axis: .horizontal, delta: 0))

  #expect(poster.events.last?.phase == 8)
}

@Test func swipeEndedResetsStateForNextGesture() {
  let poster = RecordingPoster()
  let sut = synthesizer(poster: poster, scale: 0.001)

  sut.post(DesktopSwipeUpdate(phase: .began, axis: .horizontal, delta: 500))
  sut.post(DesktopSwipeUpdate(phase: .ended, axis: .horizontal, delta: 0))
  sut.post(DesktopSwipeUpdate(phase: .changed, axis: .horizontal, delta: 300))

  #expect(poster.events.count == 2)
}

@Test func swipeCancelledResetsStateForNextGesture() {
  let poster = RecordingPoster()
  let sut = synthesizer(poster: poster, scale: 0.001)

  sut.post(DesktopSwipeUpdate(phase: .began, axis: .horizontal, delta: 500))
  sut.post(DesktopSwipeUpdate(phase: .cancelled, axis: .horizontal, delta: 0))
  sut.post(DesktopSwipeUpdate(phase: .changed, axis: .horizontal, delta: 300))

  #expect(poster.events.count == 2)
}

@Test func swipeEndedOrCancelledBeforeBeganIsIgnored() {
  let poster = RecordingPoster()
  let sut = synthesizer(poster: poster)

  sut.post(DesktopSwipeUpdate(phase: .ended, axis: .horizontal, delta: 0))
  sut.post(DesktopSwipeUpdate(phase: .cancelled, axis: .horizontal, delta: 0))

  #expect(poster.events.isEmpty)
}

@Test func swipeNegativeDeltaProducesNegativeProgress() {
  let poster = RecordingPoster()
  let sut = synthesizer(poster: poster, scale: 0.001)

  sut.post(DesktopSwipeUpdate(phase: .began, axis: .horizontal, delta: -500))
  sut.post(DesktopSwipeUpdate(phase: .changed, axis: .horizontal, delta: -300))
  sut.post(DesktopSwipeUpdate(phase: .ended, axis: .horizontal, delta: 0))

  #expect(poster.events[0].progress == -0.5)
  #expect(poster.events[1].progress == -0.8)
  #expect(poster.events.last?.phase == 4)
}

@Test func swipeExitVelocityUsesLastDelta() {
  let poster = RecordingPoster()
  let sut = synthesizer(poster: poster, scale: 0.001)

  sut.post(DesktopSwipeUpdate(phase: .began, axis: .horizontal, delta: 500))
  sut.post(DesktopSwipeUpdate(phase: .changed, axis: .horizontal, delta: 300))
  sut.post(DesktopSwipeUpdate(phase: .ended, axis: .horizontal, delta: 0))

  let endEvent = poster.events.last
  #expect(endEvent?.phase == 4)
  #expect(endEvent?.lastDelta ?? -1 == 0.3)
}

@Test func swipeFullLifecyclePostsCorrectNumberOfEvents() {
  let poster = RecordingPoster()
  let sut = synthesizer(poster: poster, scale: 0.001)

  sut.post(DesktopSwipeUpdate(phase: .began, axis: .horizontal, delta: 100))
  sut.post(DesktopSwipeUpdate(phase: .changed, axis: .horizontal, delta: 50))
  sut.post(DesktopSwipeUpdate(phase: .changed, axis: .horizontal, delta: 50))
  sut.post(DesktopSwipeUpdate(phase: .changed, axis: .horizontal, delta: 0))
  sut.post(DesktopSwipeUpdate(phase: .changed, axis: .horizontal, delta: -20))
  sut.post(DesktopSwipeUpdate(phase: .ended, axis: .horizontal, delta: 0))

  #expect(poster.events.count == 5)
  #expect(poster.events.map(\.phase) == [1, 2, 2, 2, 8])
}

@Test func swipeEndIsRepeatedSoADroppedEndCannotStrandTheTransition() async throws {
  let poster = RecordingPoster()
  let sut = synthesizer(
    poster: poster, endRepeatDelays: [.milliseconds(20), .milliseconds(40)])

  sut.post(DesktopSwipeUpdate(phase: .began, axis: .horizontal, delta: 500))
  sut.post(DesktopSwipeUpdate(phase: .ended, axis: .horizontal, delta: 0))
  try await Task.sleep(for: .milliseconds(300))

  let end = DesktopSwipeGestureEvent(axis: .horizontal, phase: 4, progress: 0.5, lastDelta: 0.5)
  #expect(poster.events.dropFirst() == [end, end, end])
}

@Test func swipeEndRepeatIsDroppedOnceTheNextSwipeStarts() async throws {
  let poster = RecordingPoster()
  let sut = synthesizer(poster: poster, endRepeatDelays: [.milliseconds(60)])

  sut.post(DesktopSwipeUpdate(phase: .began, axis: .horizontal, delta: 500))
  sut.post(DesktopSwipeUpdate(phase: .cancelled, axis: .horizontal, delta: 0))
  sut.post(DesktopSwipeUpdate(phase: .began, axis: .horizontal, delta: 100))
  try await Task.sleep(for: .milliseconds(300))

  #expect(poster.events.map(\.phase) == [1, 8, 1])
}

@Test func oneSpaceOfProgressShrinksAsDesktopsAreAdded() {
  #expect(DesktopSwipeSynthesizer.progressPerSpace(spaceCount: 1) == 2)
  #expect(DesktopSwipeSynthesizer.progressPerSpace(spaceCount: 2) == 2)
  #expect(DesktopSwipeSynthesizer.progressPerSpace(spaceCount: 3) == 1.5)
  #expect(DesktopSwipeSynthesizer.progressPerSpace(spaceCount: 5) == 1.25)
}

@Test func spacesAreCountedForTheMatchingDisplay() {
  let entries: [[String: Any]] = [
    ["Display Identifier": "A", "Spaces": [1, 2]],
    ["Display Identifier": "B", "Spaces": [1, 2, 3, 4]],
  ]
  #expect(DesktopSpaces.count(in: entries, displayIdentifier: "B") == 4)
  #expect(DesktopSpaces.count(in: entries, displayIdentifier: "C") == nil)
}

@Test func sharedSpacesAcrossDisplaysUseTheSingleMainEntry() {
  let entries: [[String: Any]] = [["Display Identifier": "Main", "Spaces": [1, 2, 3]]]
  #expect(DesktopSpaces.count(in: entries, displayIdentifier: "B") == 3)
}

@Test func verticalSwipeCarriesItsAxisToEveryEvent() async throws {
  let poster = RecordingPoster()
  let sut = DesktopSwipeSynthesizer(
    poster: poster, progressScale: { $0 == .vertical ? 0.01 : 0.001 }, endRepeatDelays: [])

  sut.post(DesktopSwipeUpdate(phase: .began, axis: .vertical, delta: 30))
  sut.post(DesktopSwipeUpdate(phase: .changed, axis: .vertical, delta: 20))
  sut.post(DesktopSwipeUpdate(phase: .ended, axis: .vertical, delta: 0))

  #expect(poster.events.map(\.axis) == [.vertical, .vertical, .vertical])
  #expect(poster.events.map(\.phase) == [1, 2, 4])
  #expect(abs((poster.events.last?.progress ?? 0) - 0.5) < 1e-9)
}
