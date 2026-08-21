/// The user-facing connection lifecycle states. Pure value type so the
/// reconciliation policy can be tested without AppKit or IOHID.
public enum ConnectionState: Equatable {
  case connecting
  case connected
  case disconnected
  case reconnecting
  case permissionRequired
  case blocked(String)
  case error

  public var title: String {
    switch self {
    case .connecting: "Connecting…"
    case .connected: "Connected"
    case .disconnected: "Mouse not found"
    case .reconnecting: "Reconnecting…"
    case .permissionRequired: "Input Monitoring required"
    case .blocked(let app): "Quit \(app) to connect"
    case .error: "Something went wrong"
    }
  }

  public var isDisconnected: Bool {
    switch self {
    case .disconnected, .reconnecting: true
    default: false
    }
  }
}
