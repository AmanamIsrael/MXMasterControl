import Foundation

/// Turns mouse-wheel ticks into the continuous, phased scrolling a trackpad produces.
///
/// Each tick adds velocity that decays exponentially, so one tick eases out over exactly its
/// own distance. While ticks keep arriving the motion is a gesture, like fingers on a
/// trackpad. When they stop, the gesture ends and the rest of the motion is reported as
/// momentum. After a fast flick the momentum glides on with the deceleration of Apple's scroll
/// views; after slow scrolling it only finishes the distance the wheel moved. A tick against
/// the direction of a glide stops it, as a finger landing on a trackpad does.
///
/// Pure and deterministic: time comes in as seconds, and output is whole points.
struct ScrollMotion: Sendable {
  struct Vector: Equatable, Sendable {
    var x: Double
    var y: Double

    static let zero = Vector(x: 0, y: 0)

    var length: Double { (x * x + y * y).squareRoot() }

    static func + (lhs: Vector, rhs: Vector) -> Vector { Vector(x: lhs.x + rhs.x, y: lhs.y + rhs.y) }
    static func - (lhs: Vector, rhs: Vector) -> Vector { Vector(x: lhs.x - rhs.x, y: lhs.y - rhs.y) }
    static func * (lhs: Vector, rhs: Double) -> Vector { Vector(x: lhs.x * rhs, y: lhs.y * rhs) }

    func dot(_ other: Vector) -> Double { x * other.x + y * other.y }
  }

  /// `CGScrollPhase` without CoreGraphics.
  enum GesturePhase: Equatable, Sendable {
    case began
    case changed
    case ended
  }

  /// `CGMomentumScrollPhase` without CoreGraphics.
  enum MomentumPhase: Equatable, Sendable {
    case began
    case changed
    case ended
  }

  /// One scroll event to post. Exactly one of the phases is set.
  struct Frame: Equatable, Sendable {
    let dx: Int32
    let dy: Int32
    let gesture: GesturePhase?
    let momentum: MomentumPhase?
  }

  struct Parameters: Sendable {
    /// How long a tick takes to ease out: about 95% of it lands within three of these.
    var tickTimeConstant = 0.06
    /// Apple's scroll views slow momentum by 0.998 per millisecond, a time constant of 0.5 s.
    var glideTimeConstant = 0.5
    /// The speed, in points per second, a gesture needs when it ends to glide on.
    var glideSpeed = 300.0
    /// Below this speed, in points per second, motion stops.
    var stopSpeed = 8.0
    /// The gesture ends once no tick has arrived for this many tick intervals...
    var liftIntervals = 3.0
    /// ...bounded by these limits, in seconds.
    var minimumLiftDelay = 0.04
    var maximumLiftDelay = 0.15
  }

  private enum State: Equatable {
    case idle
    case gesture(started: Bool)
    case momentum(started: Bool, timeConstant: Double)
  }

  let parameters: Parameters
  private var state = State.idle
  private var velocity = Vector.zero
  /// Sub-point movement not posted yet, so the total distance stays exact.
  private var remainder = Vector.zero
  private var time = 0.0
  private var lastTick = 0.0
  private var tickInterval: Double?

  init(parameters: Parameters = Parameters()) {
    self.parameters = parameters
  }

  /// True while frames remain to be produced.
  var isMoving: Bool { state != .idle }

  /// Adds a wheel tick of `delta` points at `now`. Returns frames that must be posted first:
  /// the end of a glide this tick interrupts.
  mutating func tick(_ delta: Vector, at now: Double) -> [Frame] {
    var frames = advance(to: now)
    switch state {
    case .momentum(let started, _):
      frames += finishMomentum(started: started)
      if velocity.dot(delta) < 0 {
        stop()
        return frames
      }
      state = .gesture(started: false)
      tickInterval = nil
    case .idle:
      state = .gesture(started: false)
      tickInterval = nil
    case .gesture:
      let interval = now - lastTick
      tickInterval = tickInterval.map { $0 * 0.5 + interval * 0.5 } ?? interval
    }
    velocity = velocity + delta * (1 / parameters.tickTimeConstant)
    lastTick = now
    return frames
  }

  /// Ends whatever is in progress right away, so apps never stay inside a gesture.
  mutating func interrupt() -> [Frame] {
    let frames: [Frame] =
      switch state {
      case .idle, .gesture(started: false): []
      case .gesture(started: true): [Frame(dx: 0, dy: 0, gesture: .ended, momentum: nil)]
      case .momentum(let started, _): finishMomentum(started: started)
      }
    stop()
    return frames
  }

  /// Moves time forward to `now` and returns the frames for that span.
  mutating func advance(to now: Double) -> [Frame] {
    let elapsed = now - time
    time = max(time, now)
    guard elapsed > 0 else { return [] }

    switch state {
    case .idle:
      return []

    case .gesture(let started):
      var frames: [Frame] = []
      if let frame = frame(moving: elapsed, timeConstant: parameters.tickTimeConstant,
        gesture: started ? .changed : .began, momentum: nil)
      {
        frames.append(frame)
        state = .gesture(started: true)
      }
      guard now - lastTick >= liftDelay else { return frames }
      let speed = velocity.length
      if speed < parameters.stopSpeed,
        let rest = flush(timeConstant: parameters.tickTimeConstant)
      {
        let isStarted = state == .gesture(started: true)
        frames.append(Frame(dx: rest.dx, dy: rest.dy, gesture: isStarted ? .changed : .began, momentum: nil))
        state = .gesture(started: true)
      }
      if case .gesture(started: true) = state {
        frames.append(Frame(dx: 0, dy: 0, gesture: .ended, momentum: nil))
      }
      if speed < parameters.stopSpeed {
        stop()
      } else {
        let glides = speed >= parameters.glideSpeed
        state = .momentum(
          started: false,
          timeConstant: glides ? parameters.glideTimeConstant : parameters.tickTimeConstant)
      }
      return frames

    case .momentum(let started, let timeConstant):
      var frames: [Frame] = []
      var hasStarted = started
      if let frame = frame(moving: elapsed, timeConstant: timeConstant,
        gesture: nil, momentum: started ? .changed : .began)
      {
        frames.append(frame)
        hasStarted = true
        state = .momentum(started: true, timeConstant: timeConstant)
      }
      if velocity.length < parameters.stopSpeed {
        if let rest = flush(timeConstant: timeConstant) {
          frames.append(Frame(dx: rest.dx, dy: rest.dy, gesture: nil, momentum: hasStarted ? .changed : .began))
          hasStarted = true
        }
        frames += finishMomentum(started: hasStarted)
        stop()
      }
      return frames
    }
  }

  private var liftDelay: Double {
    let delay = (tickInterval ?? .infinity) * parameters.liftIntervals
    return min(max(delay, parameters.minimumLiftDelay), parameters.maximumLiftDelay)
  }

  /// Integrates the exponential decay over `elapsed` and returns the whole points it moved.
  private mutating func frame(
    moving elapsed: Double, timeConstant: Double,
    gesture: GesturePhase?, momentum: MomentumPhase?
  ) -> Frame? {
    let decay = exp(-elapsed / timeConstant)
    remainder = remainder + velocity * (timeConstant * (1 - decay))
    velocity = velocity * decay
    let dx = remainder.x.rounded(.towardZero)
    let dy = remainder.y.rounded(.towardZero)
    guard dx != 0 || dy != 0 else { return nil }
    remainder = remainder - Vector(x: dx, y: dy)
    return Frame(dx: Int32(clamping: Int(dx)), dy: Int32(clamping: Int(dy)), gesture: gesture, momentum: momentum)
  }

  /// The whole points still owed when motion stops: the sub-point remainder plus what the
  /// remaining velocity would still travel. Rounded, so every tick lands on its full distance.
  private mutating func flush(timeConstant: Double) -> (dx: Int32, dy: Int32)? {
    let rest = remainder + velocity * timeConstant
    remainder = .zero
    velocity = .zero
    let dx = Int32(clamping: Int(rest.x.rounded()))
    let dy = Int32(clamping: Int(rest.y.rounded()))
    return dx == 0 && dy == 0 ? nil : (dx, dy)
  }

  private func finishMomentum(started: Bool) -> [Frame] {
    started ? [Frame(dx: 0, dy: 0, gesture: nil, momentum: .ended)] : []
  }

  private mutating func stop() {
    state = .idle
    velocity = .zero
    remainder = .zero
    tickInterval = nil
  }
}
