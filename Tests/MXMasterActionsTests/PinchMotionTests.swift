import CoreGraphics
import Testing

@testable import MXMasterActions

/// Feeds ticks at their times and advances frame by frame until the pinch ends.
private func run(ticks: [(time: Double, magnification: Double)]) -> [PinchMotion.Frame] {
  var motion = PinchMotion()
  var frames: [PinchMotion.Frame] = []
  var pending = ticks[...]
  var now = 0.0
  while now < 5 {
    while let next = pending.first, next.time <= now {
      frames += motion.tick(next.magnification, at: next.time)
      pending = pending.dropFirst()
    }
    frames += motion.advance(to: now)
    if pending.isEmpty, !motion.isMoving { break }
    now += 1.0 / 120
  }
  return frames
}

@Test func oneTickZoomsByExactlyItsAmountInOnePinch() {
  let frames = run(ticks: [(0, 0.1)])
  #expect(frames.first == PinchMotion.Frame(magnification: 0, phase: .began))
  #expect(frames.last == PinchMotion.Frame(magnification: 0, phase: .ended))
  #expect(frames.dropFirst().dropLast().allSatisfy { $0.phase == .changed && $0.magnification > 0 })
  #expect(frames.count > 4, "the zoom eases out over several frames")
  #expect(abs(frames.map(\.magnification).reduce(0, +) - 0.1) < 1e-9)
}

@Test func ticksWhileZoomingJoinTheSamePinch() {
  let frames = run(ticks: [(0, 0.1), (0.05, 0.1), (0.1, -0.05)])
  #expect(frames.filter { $0.phase == .began }.count == 1)
  #expect(frames.filter { $0.phase == .ended }.count == 1)
  #expect(abs(frames.map(\.magnification).reduce(0, +) - 0.15) < 1e-9)
}

@Test func interruptingEndsThePinch() {
  var motion = PinchMotion()
  _ = motion.tick(0.1, at: 0)
  #expect(motion.interrupt() == [PinchMotion.Frame(magnification: 0, phase: .ended)])
  #expect(!motion.isMoving)
  #expect(motion.interrupt().isEmpty)
}

@Test func commandScrollZoomsWhenPinchZoomIsOn() {
  let route = { (flags: CGEventFlags, inverted: Bool, features: TrackpadScrolling.Features) in
    TrackpadScrolling.route(
      vertical: 30, horizontal: 0, flags: flags, invertedFromDevice: inverted, features: features)
  }
  #expect(route(.maskCommand, false, .pinchZoom) == .zoom(30))
  // Natural scrolling flips the delta; turning the wheel away from you still zooms in.
  #expect(route(.maskCommand, true, .pinchZoom) == .zoom(-30))
  #expect(route([.maskCommand, .maskShift], false, .pinchZoom) == .zoom(30))
  #expect(route([.maskCommand, .maskAlternate], false, .pinchZoom) == nil)
  #expect(route(.maskCommand, false, .smoothScrolling) == nil)
  #expect(route([], false, .pinchZoom) == nil)
  #expect(
    route([], false, [.pinchZoom, .smoothScrolling]) == .scroll(ScrollMotion.Vector(x: 0, y: 30)))
}

@Test func thumbWheelWithCommandDoesNotZoom() {
  #expect(
    TrackpadScrolling.route(
      vertical: 0, horizontal: 12, flags: .maskCommand, invertedFromDevice: false,
      features: .pinchZoom) == nil)
}

@Test func aFastSpinNeverShrinksContentByAWholeStepAtOnce() {
  // Free-spin ticks with macOS acceleration, and a stalled frame after them.
  var motion = PinchMotion()
  var frames: [PinchMotion.Frame] = []
  for index in 0..<40 { frames += motion.tick(-3, at: Double(index) * 0.002) }
  frames += motion.advance(to: 1)
  #expect(frames.allSatisfy { $0.magnification >= -PinchMotion.Parameters().maximumPending })
  #expect(frames.last?.phase == .ended)
}
