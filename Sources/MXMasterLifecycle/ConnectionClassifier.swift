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
public enum ConnectionClassifier {
  public static func kind(of error: Error) -> ConnectionFailureKind {
    guard let channelError = error as? HIDPPChannelError else { return .fatal }
    if channelError == .inputMonitoringDenied { return .permissionRequired }
    return .transient
  }
}
