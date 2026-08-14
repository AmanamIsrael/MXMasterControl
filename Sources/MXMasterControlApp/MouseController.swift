import AppKit
import Combine
import MXMasterCore
import MXMasterHID
import ServiceManagement

@MainActor
final class MouseController: ObservableObject {
  static let shared = MouseController()

  enum ConnectionState: Equatable {
    case connecting
    case connected
    case disconnected
    case permissionRequired
    case blocked(String)
    case error(String)

    var title: String {
      switch self {
      case .connecting: "Connecting…"
      case .connected: "Connected"
      case .disconnected: "Mouse not found"
      case .permissionRequired: "Input Monitoring required"
      case .blocked(let app): "Quit \(app) to connect"
      case .error(let message): message
      }
    }
  }

  @Published private(set) var connectionState: ConnectionState = .connecting
  @Published private(set) var snapshot: MXMasterReadOnlySnapshot?
  @Published private(set) var isBusy = false
  @Published private(set) var configuration: MXMasterConfiguration
  @Published var launchAtLogin: Bool
  @Published private(set) var launchAtLoginError: String?

  private let service = MXMasterDeviceService()
  private let configurationStore: ConfigurationStore
  // This controller lives for the app's lifetime, so its observers remain registered until exit.
  // That also avoids callbacks racing actor-isolated teardown.
  private var workspaceObservers: [NSObjectProtocol] = []

  init() {
    let applicationSupport = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first!
    configurationStore = ConfigurationStore(
      fileURL:
        applicationSupport
        .appendingPathComponent("MXMasterControl", isDirectory: true)
        .appendingPathComponent("config.json")
    )
    configuration = (try? configurationStore.load()) ?? MXMasterConfiguration()
    launchAtLogin = SMAppService.mainApp.status == .enabled
    registerLifecycleObservers()
  }

  func start() {
    guard snapshot == nil, !isBusy else { return }
    refresh()
  }

  func refresh() {
    Task { await loadState(reconcile: true) }
  }

  func setDPI(_ dpi: UInt16) {
    performSettingChange {
      let state = try await self.service.setDPI(dpi)
      self.configuration.dpi = dpi
      return state
    }
  }

  func setSmartShift(mode: SmartShiftMode, threshold: UInt8) {
    performSettingChange {
      let state = try await self.service.setSmartShift(mode: mode, threshold: threshold)
      self.configuration.smartShiftMode = mode
      self.configuration.smartShiftThreshold = threshold
      return state
    }
  }

  func setWheelInverted(_ inverted: Bool) {
    performSettingChange {
      let state = try await self.service.setWheelInverted(inverted)
      self.configuration.wheelInverted = inverted
      return state
    }
  }

  func setLaunchAtLogin(_ enabled: Bool) {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      launchAtLogin = SMAppService.mainApp.status == .enabled
      launchAtLoginError = nil
    } catch {
      launchAtLogin = SMAppService.mainApp.status == .enabled
      launchAtLoginError = error.localizedDescription
    }
  }

  func openInputMonitoringSettings() {
    guard
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    else { return }
    NSWorkspace.shared.open(url)
  }

  private func performSettingChange(
    _ operation: @escaping @MainActor () async throws -> MXMasterReadOnlySnapshot
  ) {
    guard !isBusy else { return }
    Task {
      isBusy = true
      defer { isBusy = false }
      do {
        snapshot = try await operation()
        try configurationStore.save(configuration)
        connectionState = .connected
      } catch {
        connectionState = classify(error)
      }
    }
  }

  private func loadState(reconcile: Bool) async {
    guard !isBusy else { return }
    if let competitor = Self.runningCompetitor() {
      connectionState = .blocked(competitor)
      snapshot = nil
      return
    }

    isBusy = true
    connectionState = .connecting
    defer { isBusy = false }
    do {
      var state = try await service.readState()
      if reconcile {
        if let dpi = configuration.dpi, state.dpi?.current != dpi {
          state = try await service.setDPI(dpi)
        }
        if let mode = configuration.smartShiftMode {
          let threshold =
            configuration.smartShiftThreshold
            ?? state.smartShift?.autoDisengage
            ?? 10
          if state.smartShift?.wheelModeCode != mode.rawValue
            || state.smartShift?.autoDisengage != threshold
          {
            state = try await service.setSmartShift(mode: mode, threshold: threshold)
          }
        }
        if let inverted = configuration.wheelInverted, state.wheel?.inverted != inverted {
          state = try await service.setWheelInverted(inverted)
        }
      }
      snapshot = state
      connectionState = .connected
    } catch {
      snapshot = nil
      connectionState = classify(error)
    }
  }

  private func registerLifecycleObservers() {
    let center = NSWorkspace.shared.notificationCenter
    for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
      workspaceObservers.append(
        center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
          Task { @MainActor [weak self] in
            guard let self else { return }
            await service.invalidate()
            await loadState(reconcile: true)
          }
        })
    }
  }

  private func classify(_ error: Error) -> ConnectionState {
    if let channelError = error as? HIDPPChannelError {
      switch channelError {
      case .deviceNotFound: return .disconnected
      case .inputMonitoringDenied: return .permissionRequired
      default: break
      }
    }
    return .error(error.localizedDescription)
  }

  private static func runningCompetitor() -> String? {
    NSWorkspace.shared.runningApplications.lazy.compactMap(\.localizedName).first { name in
      let normalized = name.lowercased()
      return normalized.contains("logi options") || normalized == "openlogi"
    }
  }
}
