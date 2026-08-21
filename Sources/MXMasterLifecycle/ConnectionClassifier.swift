import MXMasterHID

/// How a connection failure should be handled by the reconciliation loop.
public enum ConnectionFailureKind: Equatable {
  /// A transport-level hiccup (timeout, closed channel, IO failure). These are
  /// transient and not the user's fault, so the reconnect loop keeps retrying
  /// silently instead of surfacing an error.
  case transient
  /// macOS requires Input Monitoring before any HID++ traffic can flow.
  case permissionRequired
  /// Retrying cannot fix this; surface a friendly error with a manual retry.
  case fatal
}

/// Maps connection failures to the reconciliation policy that handles them.
/// The mapping is exhaustive over `HIDPPChannelError` so a new error case is a
/// compile-time decision, not a silent fallthrough into "retry forever".
public enum ConnectionClassifier {
  public static func kind(of error: Error) -> ConnectionFailureKind {
    guard let channelError = error as? HIDPPChannelError else { return .fatal }
    switch channelError {
    case .inputMonitoringDenied:
      return .permissionRequired
    case .deviceNotFound, .managerOpenFailed, .deviceOpenFailed, .reportWriteFailed,
      .responseDeliveryFailed, .responseTimedOut, .channelClosed:
      return .transient
    case .requestAlreadyPending, .malformedResponse, .deviceError:
      // A pending-request collision means our own serialization broke; a
      // malformed response or HID++ NAK is firmware rejecting the exchange.
      // None of those heal by retrying blind, so surface them instead of
      // spinning the reconnect loop forever.
      return .fatal
    }
  }
}
