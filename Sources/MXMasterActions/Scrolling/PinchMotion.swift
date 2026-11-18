import Foundation

/// Turns wheel ticks into the magnification gesture a trackpad pinch produces.
///
/// Each tick eases out the same way a scroll tick does in `ScrollMotion`, so the zoom glides
/// instead of jumping a step per notch. Ticks that arrive while the zoom is still easing out
/// join the same pinch. Once the motion has settled, the pinch ends. A pinch has no momentum.
/// The zoom still to come is capped, so a fast spin zooms quickly but never asks an app to
/// shrink content by 100% or more in one event.
///
/// Pure and deterministic: time comes in as seconds.
struct PinchMotion: Sendable {
  /// `IOHIDEventPhaseBits` without IOKit.
  enum Phase: Equatable, Sendable {
    case began
    case changed
    case ended
  }

  /// One gesture event to post. `magnification` is the change in scale: 0.1 grows the
  /// content by about 10%.
  struct Frame: Equatable, Sendable {
    let magnification: Double
    let phase: Phase
  }

  struct Parameters: Sendable {
    /// How long a tick takes to ease out, as in `ScrollMotion`.
    var tickTimeConstant = 0.06
    /// The pinch ends once less than this much magnification is left to apply.
    var settledMagnification = 0.0005
    /// The most magnification left to apply at any time, in either direction.
    var maximumPending = 0.5
  }

  let parameters: Parameters
  private var isPinching = false
  private var velocity = 0.0
  private var time = 0.0

  init(parameters: Parameters = Parameters()) {
    self.parameters = parameters
  }

  /// True while frames remain to be produced.
  var isMoving: Bool { isPinching }

  /// Adds a tick worth `magnification` at `now`. Starts a pinch when none is in progress.
  mutating func tick(_ magnification: Double, at now: Double) -> [Frame] {
    var frames = advance(to: now)
    if !isPinching {
      isPinching = true
      // A real pinch opens with a began event before the fingers move.
      frames.append(Frame(magnification: 0, phase: .began))
    }
    let limit = parameters.maximumPending / parameters.tickTimeConstant
    velocity = min(max(velocity + magnification / parameters.tickTimeConstant, -limit), limit)
    return frames
  }

  /// Moves time forward to `now` and returns the frames for that span.
  mutating func advance(to now: Double) -> [Frame] {
    let elapsed = now - time
    time = max(time, now)
    guard isPinching, elapsed > 0 else { return [] }

    let decay = exp(-elapsed / parameters.tickTimeConstant)
    var step = velocity * parameters.tickTimeConstant * (1 - decay)
    velocity *= decay
    let remaining = velocity * parameters.tickTimeConstant
    guard abs(remaining) < parameters.settledMagnification else {
      return [Frame(magnification: step, phase: .changed)]
    }
    // Apply what is left now, so the pinch lands on the full amount of its ticks.
    step += remaining
    var frames = step == 0 ? [] : [Frame(magnification: step, phase: .changed)]
    frames += interrupt()
    return frames
  }

  /// Ends the pinch right away, so apps never stay inside a gesture.
  mutating func interrupt() -> [Frame] {
    guard isPinching else { return [] }
    isPinching = false
    velocity = 0
    return [Frame(magnification: 0, phase: .ended)]
  }
}
