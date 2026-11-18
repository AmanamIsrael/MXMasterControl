import Testing

@testable import MXMasterActions

private let frameInterval = 1.0 / 120

/// Feeds ticks at their times and advances frame by frame until the motion stops.
private func run(
  ticks: [(time: Double, dy: Double)], motion: inout ScrollMotion, until end: Double = 5
) -> [ScrollMotion.Frame] {
  var frames: [ScrollMotion.Frame] = []
  var pending = ticks[...]
  var now = 0.0
  while now < end {
    while let next = pending.first, next.time <= now {
      frames += motion.tick(ScrollMotion.Vector(x: 0, y: next.dy), at: next.time)
      pending = pending.dropFirst()
    }
    frames += motion.advance(to: now)
    if pending.isEmpty, !motion.isMoving { break }
    now += frameInterval
  }
  return frames
}

private func distance(_ frames: [ScrollMotion.Frame]) -> Int {
  frames.reduce(0) { $0 + Int($1.dy) }
}

@Test func oneTickEasesOutOverExactlyItsDistance() {
  var motion = ScrollMotion()
  let frames = run(ticks: [(0, 40)], motion: &motion)

  #expect(distance(frames) == 40)
  #expect(frames.first?.gesture == .began)
  #expect(frames.contains { $0.gesture == .ended })
  #expect(frames.count > 5)
  #expect(!motion.isMoving)
}

@Test func gestureAndMomentumPhasesComeInTrackpadOrder() {
  var motion = ScrollMotion()
  let frames = run(ticks: [(0, 40)], motion: &motion)
  let phases = frames.map { frame -> String in
    switch (frame.gesture, frame.momentum) {
    case (.began?, _): "began"
    case (.changed?, _): "changed"
    case (.ended?, _): "ended"
    case (_, .began?): "momentumBegan"
    case (_, .changed?): "momentum"
    case (_, .ended?): "momentumEnded"
    default: "none"
    }
  }
  let order = ["began", "changed", "ended", "momentumBegan", "momentum", "momentumEnded"]
  let ranks = phases.map { order.firstIndex(of: $0) ?? -1 }
  #expect(!ranks.contains(-1))
  #expect(ranks == ranks.sorted())
  #expect(phases.last == "momentumEnded")
}

@Test func onlyEndFramesCarryNoMovement() {
  var motion = ScrollMotion()
  let frames = run(ticks: [(0, 40), (0.02, 40), (0.04, 40)], motion: &motion)

  for frame in frames where frame.dx == 0 && frame.dy == 0 {
    #expect(frame.gesture == .ended || frame.momentum == .ended)
  }
}

@Test func aFastFlickGlidesPastTheWheelDistance() {
  var motion = ScrollMotion()
  let ticks = (0..<10).map { (time: Double($0) * 0.015, dy: 60.0) }
  let frames = run(ticks: ticks, motion: &motion)

  #expect(distance(frames) > 600 + 200)
  #expect(frames.contains { $0.momentum == .began })
}

@Test func slowTicksStopWhereTheWheelStopped() {
  var motion = ScrollMotion()
  let ticks = (0..<4).map { (time: Double($0) * 0.4, dy: 20.0) }
  let frames = run(ticks: ticks, motion: &motion)

  #expect(distance(frames) == 80)
}

@Test func aTickAgainstAGlideStopsItLikeAFingerOnTheTrackpad() {
  var motion = ScrollMotion()
  let flick = (0..<10).map { (time: Double($0) * 0.015, dy: 60.0) }
  var frames = run(ticks: flick, motion: &motion, until: 0.4)
  #expect(motion.isMoving)

  frames = motion.tick(ScrollMotion.Vector(x: 0, y: -10), at: 0.41)

  #expect(frames.last?.momentum == .ended)
  #expect(!motion.isMoving)
  #expect(motion.advance(to: 0.5).isEmpty)
}

@Test func aTickWithAGlideEndsTheGlideAndStartsANewGesture() {
  var motion = ScrollMotion()
  let flick = (0..<10).map { (time: Double($0) * 0.015, dy: 60.0) }
  _ = run(ticks: flick, motion: &motion, until: 0.4)

  let interrupted = motion.tick(ScrollMotion.Vector(x: 0, y: 10), at: 0.41)
  let next = motion.advance(to: 0.42)

  #expect(interrupted.last?.momentum == .ended)
  #expect(next.first?.gesture == .began)
}

@Test func interruptingClosesTheOpenPhase() {
  var motion = ScrollMotion()
  _ = motion.tick(ScrollMotion.Vector(x: 0, y: 40), at: 0)
  _ = motion.advance(to: frameInterval)

  #expect(motion.interrupt() == [ScrollMotion.Frame(dx: 0, dy: 0, gesture: .ended, momentum: nil)])
  #expect(!motion.isMoving)
  #expect(motion.interrupt().isEmpty)
}
