import Foundation

/// Serializes requests while coalescing requests that arrive during an in-flight
/// request down to the most recent one. Pure state machine; the owner drives it
/// by submitting requests and advancing it with `finishCurrent()`.
public struct LatestOperationQueue<Operation> {
  private(set) public var isRunning = false
  private(set) public var pending: Operation?
  private(set) public var current: Operation?

  public init() {}

  /// Submits a request. Returns `true` when the queue was idle and this request
  /// should start now, or `false` when a request is already running (this request
  /// replaces any queued request and runs next).
  public mutating func submit(_ operation: Operation) -> Bool {
    if isRunning {
      pending = operation
      return false
    }
    current = operation
    isRunning = true
    return true
  }

  /// Marks the current request complete. Returns the next request to run, or
  /// `nil` when the queue is empty (the queue becomes idle).
  public mutating func finishCurrent() -> Operation? {
    if let pending {
      current = pending
      self.pending = nil
      return current
    }
    current = nil
    isRunning = false
    return nil
  }

  /// Discards the current and any queued request; the queue becomes idle.
  public mutating func abandon() {
    current = nil
    pending = nil
    isRunning = false
  }
}