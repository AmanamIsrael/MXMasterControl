import AppKit
import Combine
import MXMasterActions
import MXMasterCore
import MXMasterHID
import os
import ServiceManagement

@MainActor
final class MouseController: ObservableObject {
  static let shared = MouseController()

  private static let logger = Logger(
    subsystem: "com.amanamisrael.MXMasterControl",
    category: "connection"
  )

  enum ConnectionState: Equatable {
    case connecting
    case connected
    case disconnected
    case reconnecting
    case permissionRequired
    case blocked(String)
    case error

    var title: String {
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

    var isDisconnected: Bool {
      switch self {
      case .disconnected, .reconnecting: true
      default: false
      }
    }
  }

  @Published private(set) var connectionState: ConnectionState = .connecting
  @Published private(set) var snapshot: MXMasterReadOnlySnapshot?
  @Published private(set) var isBusy = false
  @Published private(set) var configuration: MXMasterConfiguration
  @Published var launchAtLogin: Bool
  @Published private(set) var launchAtLoginError: String?
  @Published private(set) var accessibilityGranted: Bool
  @Published private(set) var actionError: String?
  @Published private(set) var controlCaptureActive = false

  private lazy var service = MXMasterDeviceService { [weak self] in
    Task { @MainActor [weak self] in
      self?.handleDeviceDisconnected()
    }
  }
  private let configurationStore: ConfigurationStore
  private let actionCoordinator: MouseActionCoordinator
  // This controller lives for the app's lifetime, so its observers remain registered until exit.
  // That also avoids callbacks racing actor-isolated teardown.
  private var workspaceObservers: [NSObjectProtocol] = []
  private var applicationObservers: [NSObjectProtocol] = []
  private var reconnectTask: Task<Void, Never>?
  private var pendingSettingTask: Task<Void, Never>?
  private var settingQueue = LatestOperationQueue<
    @MainActor () async throws -> MXMasterReadOnlySnapshot
  >()
  private var settingGeneration = 0
  private var isSleeping = false

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
    let loadedConfiguration = (try? configurationStore.load()) ?? MXMasterConfiguration()
    configuration = loadedConfiguration
    actionCoordinator = MouseActionCoordinator(configuration: loadedConfiguration)
    launchAtLogin = SMAppService.mainApp.status == .enabled
    accessibilityGranted = MouseActionDispatcher.accessibilityGranted
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
      let supported = self.snapshot?.dpi?.supported
      let state = try await self.service.setDPI(dpi, supportedDPIs: supported)
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

  func setAction(_ action: MouseAction, for control: MouseControl) {
    configuration.setAction(action, for: control)
    persistAndApplyActions()
  }

  func setGestureNavigationEnabled(_ enabled: Bool) {
    configuration.gestureNavigationEnabled = enabled
    persistAndApplyActions()
  }

  func setGestureAction(_ action: MouseAction, for direction: GestureDirection) {
    configuration.gestureActions.setAction(action, for: direction)
    persistAndApplyActions()
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

  func requestInputMonitoringAccess() {
    let access = IOHIDDeviceEnumerator().requestListenAccess()
    if access == .granted {
      Task {
        await service.invalidate()
        await loadState(reconcile: true)
      }
    } else {
      connectionState = .permissionRequired
    }
  }

  func requestAccessibilityAccess() {
    accessibilityGranted = MouseActionDispatcher.requestAccessibility()
    Task { await applyActionConfiguration() }
  }

  func openAccessibilitySettings() {
    guard
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    else { return }
    NSWorkspace.shared.open(url)
  }

  func shutdown() async {
    reconnectTask?.cancel()
    reconnectTask = nil
    actionCoordinator.cancelPendingGesture()
    await service.invalidate()
  }

  private func performSettingChange(
    _ operation: @escaping @MainActor () async throws -> MXMasterReadOnlySnapshot
  ) {
    guard settingQueue.submit(operation) else { return }
    guard !isBusy else { return }
    startSettingLoop()
  }

  private func startSettingLoop() {
    guard let first = settingQueue.current else { return }
    settingGeneration += 1
    let generation = settingGeneration
    pendingSettingTask = Task {
      isBusy = true
      defer {
        if settingGeneration == generation {
          isBusy = false
          pendingSettingTask = nil
        }
      }
      var nextOperation = first
      while true {
        let state: MXMasterReadOnlySnapshot
        do {
          state = try await nextOperation()
        } catch {
          failSettingChange(error, generation: generation)
          return
        }
        guard !Task.isCancelled, settingGeneration == generation else { return }
        snapshot = state
        do {
          try configurationStore.save(configuration)
          connectionState = .connected
        } catch {
          failSettingChange(error, generation: generation)
          return
        }
        guard !Task.isCancelled, settingGeneration == generation else { return }
        guard let queued = settingQueue.finishCurrent() else { return }
        nextOperation = queued
      }
    }
  }

  private func failSettingChange(_ error: Error, generation: Int) {
    guard settingGeneration == generation else { return }
    settingQueue.abandon()
    let classifiedState = classify(error)
    connectionState = classifiedState
    if classifiedState.isDisconnected {
      handleDeviceDisconnected()
    }
  }

  private func loadState(reconcile: Bool) async {
    if isBusy { return }
    if let competitor = Self.runningCompetitor() {
      connectionState = .blocked(competitor)
      snapshot = nil
      return
    }

    isBusy = true
    if !connectionState.isDisconnected { connectionState = .connecting }
    defer { isBusy = false }
    do {
      let state = try await service.readState()
      var didWrite = false
      if reconcile {
        if let dpi = configuration.dpi, state.dpi?.current != dpi {
          try await service.applyDPI(dpi, supportedDPIs: state.dpi?.supported)
          didWrite = true
        }
        if let mode = configuration.smartShiftMode {
          let threshold =
            configuration.smartShiftThreshold
            ?? state.smartShift?.autoDisengage
            ?? 10
          if state.smartShift?.wheelModeCode != mode.rawValue
            || state.smartShift?.autoDisengage != threshold
          {
            try await service.applySmartShift(mode: mode, threshold: threshold)
            didWrite = true
          }
        }
        if let inverted = configuration.wheelInverted, state.wheel?.inverted != inverted {
          try await service.applyWheelInverted(inverted)
          didWrite = true
        }
      }
      snapshot = didWrite ? try await service.readState() : state
      connectionState = .connected
      reconnectTask?.cancel()
      reconnectTask = nil
      await applyActionConfiguration()
      if settingQueue.isRunning { startSettingLoop() }
    } catch {
      settingQueue.abandon()
      snapshot = nil
      let classifiedState = classify(error)
      connectionState = classifiedState
      if classifiedState.isDisconnected { startReconnectLoop() }
    }
  }

  private func registerLifecycleObservers() {
    let center = NSWorkspace.shared.notificationCenter
    for name in [NSWorkspace.willSleepNotification] {
      workspaceObservers.append(
        center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
          Task { @MainActor [weak self] in
            guard let self else { return }
            isSleeping = true
            reconnectTask?.cancel()
            reconnectTask = nil
            pendingSettingTask?.cancel()
            pendingSettingTask = nil
            settingQueue.abandon()
            isBusy = false
            snapshot = nil
            controlCaptureActive = false
            await service.invalidate()
            connectionState = .disconnected
          }
        })
    }

    for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
      workspaceObservers.append(
        center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
          Task { @MainActor [weak self] in
            guard let self else { return }
            guard isSleeping else { return }
            isSleeping = false
            await service.invalidate()
            let ready = await service.waitForDevice(timeout: 3)
            guard !isSleeping else { return }
            if ready {
              await loadState(reconcile: true)
            } else {
              connectionState = .reconnecting
              startReconnectLoop()
            }
          }
        })
    }

    applicationObservers.append(
      NotificationCenter.default.addObserver(
        forName: NSApplication.didBecomeActiveNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        Task { @MainActor [weak self] in
          guard let self else { return }
          accessibilityGranted = MouseActionDispatcher.accessibilityGranted
          await applyActionConfiguration()
        }
      })
  }

  private func persistAndApplyActions() {
    do {
      try configurationStore.save(configuration)
      actionCoordinator.update(configuration: configuration)
      Task { await applyActionConfiguration() }
    } catch {
      actionError = error.localizedDescription
    }
  }

  private func handleDeviceDisconnected() {
    Self.logger.info("Device disconnected; starting silent reconnect loop")
    actionCoordinator.cancelPendingGesture()
    pendingSettingTask?.cancel()
    pendingSettingTask = nil
    settingQueue.abandon()
    snapshot = nil
    isBusy = false
    connectionState = .reconnecting
    controlCaptureActive = false
    startReconnectLoop()
  }

  private func startReconnectLoop() {
    guard reconnectTask == nil else { return }
    reconnectTask = Task { [weak self] in
      defer { self?.reconnectTask = nil }
      var delay: UInt64 = 1_000_000_000
      // A short cap keeps recovery snappy when the mouse comes back (e.g. it
      // wakes as soon as the user moves it) while staying quiet and cheap.
      let maxDelay: UInt64 = 10_000_000_000
      while !Task.isCancelled {
        do {
          try await Task.sleep(for: .milliseconds(500))
        } catch {
          return
        }
        guard let self, self.connectionState.isDisconnected else { return }
        await self.loadState(reconcile: true)
        if self.connectionState == .connected {
          Self.logger.info("Reconnected to device")
          return
        }
        Self.logger.debug("Reconnect attempt failed; retrying in \(Double(delay) / 1_000_000_000, format: .fixed(precision: 1))s")
        delay = min(delay * 2, maxDelay)
        do {
          try await Task.sleep(for: .nanoseconds(delay))
        } catch {
          return
        }
      }
    }
  }

  private func applyActionConfiguration() async {
    actionCoordinator.update(configuration: configuration)
    accessibilityGranted = MouseActionDispatcher.accessibilityGranted
    let requests = ControlCapturePlanner.requests(for: configuration)

    if configuration.requiresAccessibility, !accessibilityGranted {
      do {
        try await service.configureControlCapture(requests: []) { _ in }
        controlCaptureActive = false
      } catch {
        actionError = error.localizedDescription
        return
      }
      actionError = "Accessibility is required before custom button actions can be enabled."
      return
    }

    do {
      let coordinator = actionCoordinator
      try await service.configureControlCapture(requests: requests) { event in
        coordinator.handle(event)
      }
      controlCaptureActive = !requests.isEmpty
      actionError = nil
    } catch {
      controlCaptureActive = false
      actionError = error.localizedDescription
    }
  }

  /// Maps a failure to the connection state it should produce. Transport-level
  /// HID++ errors (timeouts, closed channels, IO failures) are treated as
  /// transient: they are not the user's fault, so they keep the silent
  /// reconnect loop running instead of surfacing an error. Only faults that
  /// retrying cannot fix become `.error`.
  private func classify(_ error: Error) -> ConnectionState {
    Self.logger.error("Connection operation failed: \(error.localizedDescription, privacy: .public)")
    if let channelError = error as? HIDPPChannelError {
      switch channelError {
      case .inputMonitoringDenied: return .permissionRequired
      default: return .reconnecting
      }
    }
    return .error
  }

  private static func runningCompetitor() -> String? {
    NSWorkspace.shared.runningApplications.lazy.compactMap(\.localizedName).first { name in
      let normalized = name.lowercased()
      return normalized.contains("logi options") || normalized == "openlogi"
    }
  }
}
