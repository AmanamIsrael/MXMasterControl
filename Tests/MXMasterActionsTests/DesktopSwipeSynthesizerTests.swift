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
  scale: Double = 0.001
) -> DesktopSwipeSynthesizer {
  DesktopSwipeSynthesizer(poster: poster, progressScale: { scale })
}

@Test func swipeBeganPostsPhaseOneWithScaledProgress() {
  let poster = RecordingPoster()
  let sut = synthesizer(poster: poster, scale: 0.001)

  sut.post(DesktopSwipeUpdate(phase: .began, deltaX: 500))

  #expect(poster.events == [
    DesktopSwipeGestureEvent(phase: 1, progress: 0.5, lastDelta: 0.5),
  ])
}

@Test func swipeChangedAccumulatesProgressAndPostsPhaseTwo() {
  let poster = RecordingPoster()
  let sut = synthesizer(poster: poster, scale: 0.001)

  sut.post(DesktopSwipeUpdate(phase: .began, deltaX: 500))
  sut.post(DesktopSwipeUpdate(phase: .changed, deltaX: 300))
  sut.post(DesktopSwipeUpdate(phase: .changed, deltaX: 200))

  #expect(poster.events.count == 3)
  #expect(poster.events[1] == DesktopSwipeGestureEvent(phase: 2, progress: 0.8, lastDelta: 0.3))
  #expect(poster.events[2] == DesktopSwipeGestureEvent(phase: 2, progress: 1.0, lastDelta: 0.2))
}

@Test func swipeChangedWithZeroDeltaIsIgnored() {
  let poster = RecordingPoster()
  let sut = synthesizer(poster: poster)

  sut.post(DesktopSwipeUpdate(phase: .began, deltaX: 500))
  sut.post(DesktopSwipeUpdate(phase: .changed, deltaX: 0))

  #expect(poster.events.count == 1)
}

@Test func swipeChangedBeforeBeganIsIgnored() {
  let poster = RecordingPoster()
  let sut = synthesizer(poster: poster)

  sut.post(DesktopSwipeUpdate(phase: .changed, deltaX: 100))

  #expect(poster.events.isEmpty)
}

@Test func swipeEndedCommitsWhenDirectionMatchesProgress() {
  let poster = RecordingPoster()
  let sut = synthesizer(poster: poster, scale: 0.001)

  sut.post(DesktopSwipeUpdate(phase: .began, deltaX: 500))
  sut.post(DesktopSwipeUpdate(phase: .changed, deltaX: 300))
  sut.post(DesktopSwipeUpdate(phase: .ended, deltaX: 0))

  #expect(poster.events.last?.phase == 4)
  #expect(poster.events.last?.progress ?? -1 == 0.8)
}

@Test func swipeEndedCancelsWhenDirectionOpposesProgress() {
  let poster = RecordingPoster()
  let sut = synthesizer(poster: poster, scale: 0.001)

  sut.post(DesktopSwipeUpdate(phase: .began, deltaX: 500))
  sut.post(DesktopSwipeUpdate(phase: .changed, deltaX: -200))
  sut.post(DesktopSwipeUpdate(phase: .ended, deltaX: 0))

  #expect(poster.events.last?.phase == 8)
}

@Test func swipeEndedCommitsWhenProgressIsZero() {
  let poster = RecordingPoster()
  let sut = synthesizer(poster: poster, scale: 0.001)

  sut.post(DesktopSwipeUpdate(phase: .began, deltaX: 0))
  sut.post(DesktopSwipeUpdate(phase: .ended, deltaX: 0))

  #expect(poster.events.last?.phase == 4)
}

@Test func swipeCancelledPostsPhaseEight() {
  let poster = RecordingPoster()
  let sut = synthesizer(poster: poster, scale: 0.001)

  sut.post(DesktopSwipeUpdate(phase: .began, deltaX: 500))
  sut.post(DesktopSwipeUpdate(phase: .changed, deltaX: 300))
  sut.post(DesktopSwipeUpdate(phase: .cancelled, deltaX: 0))

  #expect(poster.events.last?.phase == 8)
}

@Test func swipeEndedResetsStateForNextGesture() {
  let poster = RecordingPoster()
  let sut = synthesizer(poster: poster, scale: 0.001)

  sut.post(DesktopSwipeUpdate(phase: .began, deltaX: 500))
  sut.post(DesktopSwipeUpdate(phase: .ended, deltaX: 0))
  sut.post(DesktopSwipeUpdate(phase: .changed, deltaX: 300))

  #expect(poster.events.count == 2)
}

@Test func swipeCancelledResetsStateForNextGesture() {
  let poster = RecordingPoster()
  let sut = synthesizer(poster: poster, scale: 0.001)

  sut.post(DesktopSwipeUpdate(phase: .began, deltaX: 500))
  sut.post(DesktopSwipeUpdate(phase: .cancelled, deltaX: 0))
  sut.post(DesktopSwipeUpdate(phase: .changed, deltaX: 300))

  #expect(poster.events.count == 2)
}

@Test func swipeEndedOrCancelledBeforeBeganIsIgnored() {
  let poster = RecordingPoster()
  let sut = synthesizer(poster: poster)

  sut.post(DesktopSwipeUpdate(phase: .ended, deltaX: 0))
  sut.post(DesktopSwipeUpdate(phase: .cancelled, deltaX: 0))

  #expect(poster.events.isEmpty)
}

@Test func swipeNegativeDeltaProducesNegativeProgress() {
  let poster = RecordingPoster()
  let sut = synthesizer(poster: poster, scale: 0.001)

  sut.post(DesktopSwipeUpdate(phase: .began, deltaX: -500))
  sut.post(DesktopSwipeUpdate(phase: .changed, deltaX: -300))
  sut.post(DesktopSwipeUpdate(phase: .ended, deltaX: 0))

  #expect(poster.events[0].progress == -0.5)
  #expect(poster.events[1].progress == -0.8)
  #expect(poster.events.last?.phase == 4)
}

@Test func swipeExitVelocityUsesLastDelta() {
  let poster = RecordingPoster()
  let sut = synthesizer(poster: poster, scale: 0.001)

  sut.post(DesktopSwipeUpdate(phase: .began, deltaX: 500))
  sut.post(DesktopSwipeUpdate(phase: .changed, deltaX: 300))
  sut.post(DesktopSwipeUpdate(phase: .ended, deltaX: 0))

  let endEvent = poster.events.last
  #expect(endEvent?.phase == 4)
  #expect(endEvent?.lastDelta ?? -1 == 0.3)
}

@Test func swipeFullLifecyclePostsCorrectNumberOfEvents() {
  let poster = RecordingPoster()
  let sut = synthesizer(poster: poster, scale: 0.001)

  sut.post(DesktopSwipeUpdate(phase: .began, deltaX: 100))
  sut.post(DesktopSwipeUpdate(phase: .changed, deltaX: 50))
  sut.post(DesktopSwipeUpdate(phase: .changed, deltaX: 50))
  sut.post(DesktopSwipeUpdate(phase: .changed, deltaX: 0))
  sut.post(DesktopSwipeUpdate(phase: .changed, deltaX: -20))
  sut.post(DesktopSwipeUpdate(phase: .ended, deltaX: 0))

  #expect(poster.events.count == 5)
  #expect(poster.events.map(\.phase) == [1, 2, 2, 2, 8])
}
