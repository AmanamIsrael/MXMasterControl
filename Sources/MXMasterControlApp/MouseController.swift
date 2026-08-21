import AppKit
import Combine
import MXMasterActions
import MXMasterCore
import MXMasterHID
import MXMasterLifecycle
import os
import ServiceManagement

@MainActor
final class MouseController: ObservableObject {
  static let shared = MouseController()

  private static let logger = Logger(
    subsystem: "com.amanamisrael.MXMasterControl",
    category: "connection"
  )

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
  private var reconnectGeneration = 0
  private var pendingSettingTask: Task<Void, Never>?
  private var settingLoopRunning = false
  private var pendingSettings: [SettingKind: SettingOperation] = [:]
  private var settingGeneration = 0
  private var isSleeping = false
  private let deviceMonitor = HIDPPDeviceMonitor()
  private var lastArrivalHandling = Date.distantPast

  /// Independent settings coalesce separately: moving the DPI slider must not
  /// discard a queued wheel toggle (or vice versa).
  private enum SettingKind: CaseIterable {
    case dpi
    case smartShift
    case wheel
  }

  private typealias SettingOperation = @MainActor () async throws -> MXMasterReadOnlySnapshot

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
    startDeviceMonitor()
  }

  func start() {
    guard snapshot == nil, !isBusy else { return }
    refresh()
  }

  func refresh() {
    Task { await loadState(reconcile: true) }
  }

  func setDPI(_ dpi: UInt16) {
    performSettingChange(kind: .dpi) {
      let supported = self.snapshot?.dpi?.supported
      let state = try await self.service.setDPI(dpi, supportedDPIs: supported)
      self.configuration.dpi = dpi
      return state
    }
  }

  func setSmartShift(mode: SmartShiftMode, threshold: UInt8) {
    performSettingChange(kind: .smartShift) {
      let state = try await self.service.setSmartShift(mode: mode, threshold: threshold)
      self.configuration.smartShiftMode = mode
      self.configuration.smartShiftThreshold = threshold
      return state
    }
  }

  func setWheelInverted(_ inverted: Bool) {
    performSettingChange(kind: .wheel) {
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
        // A first-launch start may have failed with kIOReturnNotPermitted and
        // torn its handler down; retry now that permission is granted.
        startDeviceMonitor()
        await loadState(reconcile: true)
      }
    } else {
      connectionState = .permissionRequired
    }
  }

  private func startDeviceMonitor() {
    deviceMonitor.start { [weak self] in
      Task { @MainActor [weak self] in self?.deviceDidArrive() }
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
    deviceMonitor.stop()
    await service.invalidate()
  }

  private func performSettingChange(
    kind: SettingKind,
    _ operation: @escaping @MainActor () async throws -> MXMasterReadOnlySnapshot
  ) {
    pendingSettings[kind] = operation
    guard !settingLoopRunning else { return }
    startSettingLoop()
  }

  /// Removes the next queued operation, FIFO across settings and latest-wins
  /// within each setting.
  private func takeNextPendingSetting() -> SettingOperation? {
    for kind in SettingKind.allCases {
      if let operation = pendingSettings.removeValue(forKey: kind) { return operation }
    }
    return nil
  }

  private func abandonPendingSettings() {
    pendingSettings.removeAll()
  }

  private func startSettingLoop() {
    guard !settingLoopRunning, let first = takeNextPendingSetting() else { return }
    settingLoopRunning = true
    settingGeneration += 1
    let generation = settingGeneration
    pendingSettingTask = Task {
      isBusy = true
      defer {
        if settingGeneration == generation {
          isBusy = false
          pendingSettingTask = nil
        }
        settingLoopRunning = false
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
        guard let queued = takeNextPendingSetting() else { return }
        nextOperation = queued
      }
    }
  }

  private func failSettingChange(_ error: Error, generation: Int) {
    guard settingGeneration == generation else { return }
    abandonPendingSettings()
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
      if !pendingSettings.isEmpty { startSettingLoop() }
    } catch {
      abandonPendingSettings()
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
            abandonPendingSettings()
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
    abandonPendingSettings()
    snapshot = nil
    isBusy = false
    connectionState = .reconnecting
    controlCaptureActive = false
    startReconnectLoop()
  }

  /// The IOHID monitor reported the target device appearing. Recovery becomes
  /// independent of the backoff curve: restart the loop right away (or refresh
  /// out of a fatal error, since power-cycling the mouse is the classic fix).
  private func deviceDidArrive() {
    guard !isSleeping else { return }
    guard connectionState.isDisconnected || connectionState == .error else { return }
    let now = Date()
    guard now.timeIntervalSince(lastArrivalHandling) >= 1 else { return }
    lastArrivalHandling = now
    Self.logger.info("Device arrival detected; retrying now")
    if connectionState.isDisconnected {
      reconnectTask?.cancel()
      reconnectTask = nil
      startReconnectLoop()
    } else {
      refresh()
    }
  }

  private func startReconnectLoop() {
    guard reconnectTask == nil else { return }
    reconnectGeneration += 1
    let generation = reconnectGeneration
    var schedule = ReconnectSchedule()
    reconnectTask = Task { [weak self] in
      // Only clear the handle if no newer loop replaced this one.
      defer {
        if self?.reconnectGeneration == generation { self?.reconnectTask = nil }
      }
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
        Self.logger.debug(
          "Reconnect attempt failed; retrying in \(schedule.delay.components.seconds)s"
        )
        schedule.advance()
        do {
          try await Task.sleep(for: schedule.delay)
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

  /// Maps a failure to the connection state it should produce. The policy
  /// lives in MXMasterLifecycle so it stays testable without AppKit or IOHID.
  private func classify(_ error: Error) -> ConnectionState {
    Self.logger.error("Connection operation failed: \(error.localizedDescription, privacy: .public)")
    switch ConnectionClassifier.kind(of: error) {
    case .transient: return .reconnecting
    case .permissionRequired: return .permissionRequired
    case .fatal: return .error
    }
  }

  private static func runningCompetitor() -> String? {
    NSWorkspace.shared.runningApplications.lazy.compactMap(\.localizedName).first { name in
      let normalized = name.lowercased()
      return normalized.contains("logi options") || normalized == "openlogi"
    }
  }
}
