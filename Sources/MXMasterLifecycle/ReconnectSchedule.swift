/// Exponential backoff for the silent reconnect loop. Doubles from 1 s up to a
/// 30 s cap so an absent mouse costs almost nothing to wait out. Recovery does
/// not depend on this curve: a device-arrival event restarts the loop
/// immediately, and `reset()` returns to the base delay after such a restart so
/// a device that appeared but was not ready yet is retried quickly.
public struct ReconnectSchedule: Sendable, Equatable {
  public static let baseDelay: Duration = .seconds(1)
  public static let maxDelay: Duration = .seconds(30)

  public private(set) var delay: Duration

  public init() {
    delay = Self.baseDelay
  }

  public mutating func advance() {
    delay = delay * 2
    if delay > Self.maxDelay { delay = Self.maxDelay }
  }

  public mutating func reset() {
    delay = Self.baseDelay
  }
}
