import Foundation
import MXMasterCore

public enum MXMasterServiceError: LocalizedError, Equatable {
  case featureUnavailable(UInt16)
  case unsupportedDPI(UInt16)
  case invalidSmartShiftThreshold(UInt8)
  case verificationFailed(setting: String)

  public var errorDescription: String? {
    switch self {
    case .featureUnavailable(let feature):
      String(format: "The mouse does not expose required HID++ feature 0x%04x.", feature)
    case .unsupportedDPI(let dpi): "The mouse does not report \(dpi) DPI as supported."
    case .invalidSmartShiftThreshold(let threshold):
      "SmartShift threshold \(threshold) is outside the supported 1–254 range."
    case .verificationFailed(let setting): "The mouse did not confirm the requested \(setting)."
    }
  }
}

/// A persistent, single-owner service for the app. All synchronous IOHID work runs on one private
/// serial queue, keeping it off the main actor and preventing overlapping HID++ requests.
public final class MXMasterDeviceService: @unchecked Sendable {
  private let queue = DispatchQueue(label: "com.amanamisrael.MXMasterControl.device-service")
  private var channel: (any HIDPPChannel)?
  private var protocolInfo: HIDPPProbeResult?
  private var captureSession: HIDPPControlCaptureSession?
  private var connectionGeneration: UInt64 = 0
  private var lastCaptureRequests: [ControlCaptureRequest] = []
  private var cachedProbeResult: HIDPPProbeResult?
  private let disconnectHandler: @Sendable () -> Void
  private let channelFactory: @Sendable (@escaping @Sendable () -> Void) throws -> any HIDPPChannel

  public init(
    onDisconnect: @escaping @Sendable () -> Void = {},
    channelFactory: @escaping @Sendable (@escaping @Sendable () -> Void) throws
      -> any HIDPPChannel = { onDisconnect in
        try HIDPPDeviceChannel(onDisconnect: onDisconnect)
      }
  ) {
    disconnectHandler = onDisconnect
    self.channelFactory = channelFactory
  }

  deinit {
    try? captureSession?.close()
    channel?.close()
  }

  public func readState() async throws -> MXMasterReadOnlySnapshot {
    try await perform { service in
      let (channel, protocolInfo) = try service.connection()
      return try HIDPPReadOnlyProbe().readState(channel: channel, protocolInfo: protocolInfo)
    }
  }

  public func setDPI(_ dpi: UInt16, supportedDPIs: [UInt16]? = nil) async throws -> MXMasterReadOnlySnapshot {
    try await perform { service in
      let (channel, protocolInfo) = try service.connection()
      guard let index = protocolInfo.index(of: HIDPPFeatureID.adjustableDPI) else {
        throw MXMasterServiceError.featureUnavailable(HIDPPFeatureID.adjustableDPI)
      }
      if let supportedDPIs {
        guard supportedDPIs.contains(dpi) else {
          throw MXMasterServiceError.unsupportedDPI(dpi)
        }
      } else {
        let before = try HIDPPReadOnlyProbe().readDPIOnly(channel: channel, protocolInfo: protocolInfo)
        guard before?.supported.contains(dpi) == true else {
          throw MXMasterServiceError.unsupportedDPI(dpi)
        }
      }
      _ = try channel.send(
        HIDPPMessage(
          featureIndex: index,
          functionID: 3,
          payload: [0, UInt8(dpi >> 8), UInt8(dpi & 0xFF)]
        ))
      let probe = HIDPPReadOnlyProbe()
      let dpiSnapshot = try probe.readDPIOnly(channel: channel, protocolInfo: protocolInfo)
      guard dpiSnapshot?.current == dpi else {
        throw MXMasterServiceError.verificationFailed(setting: "DPI")
      }
      let fullState = try probe.readState(channel: channel, protocolInfo: protocolInfo)
      return fullState
    }
  }

  public func setSmartShift(
    mode: SmartShiftMode,
    threshold: UInt8
  ) async throws -> MXMasterReadOnlySnapshot {
    guard (1...254).contains(threshold) else {
      throw MXMasterServiceError.invalidSmartShiftThreshold(threshold)
    }
    return try await perform { service in
      let (channel, protocolInfo) = try service.connection()
      guard let index = protocolInfo.index(of: HIDPPFeatureID.smartShift) else {
        throw MXMasterServiceError.featureUnavailable(HIDPPFeatureID.smartShift)
      }
      _ = try channel.send(
        HIDPPMessage(
          featureIndex: index,
          functionID: 1,
          payload: [mode.rawValue, threshold, 0]
        ))
      let after = try HIDPPReadOnlyProbe().readState(channel: channel, protocolInfo: protocolInfo)
      guard
        after.smartShift?.wheelModeCode == mode.rawValue,
        after.smartShift?.autoDisengage == threshold
      else { throw MXMasterServiceError.verificationFailed(setting: "SmartShift state") }
      return after
    }
  }

  public func setWheelInverted(_ inverted: Bool) async throws -> MXMasterReadOnlySnapshot {
    try await perform { service in
      let (channel, protocolInfo) = try service.connection()
      guard let index = protocolInfo.index(of: HIDPPFeatureID.wheel) else {
        throw MXMasterServiceError.featureUnavailable(HIDPPFeatureID.wheel)
      }
      let current = try channel.send(HIDPPMessage(featureIndex: index, functionID: 1))
      var modeByte = current.payload[0]
      if inverted { modeByte |= 1 << 2 } else { modeByte &= ~(1 << 2) }
      _ = try channel.send(
        HIDPPMessage(featureIndex: index, functionID: 2, payload: [modeByte, 0, 0])
      )
      let after = try HIDPPReadOnlyProbe().readState(channel: channel, protocolInfo: protocolInfo)
      guard after.wheel?.inverted == inverted else {
        throw MXMasterServiceError.verificationFailed(setting: "wheel direction")
      }
      return after
    }
  }

  /// Applies DPI without a redundant full state read. Verifies with a targeted
  /// DPI read-back only. Use `readState()` separately for the full snapshot.
  public func applyDPI(_ dpi: UInt16, supportedDPIs: [UInt16]? = nil) async throws {
    try await perform { service in
      let (channel, protocolInfo) = try service.connection()
      guard let index = protocolInfo.index(of: HIDPPFeatureID.adjustableDPI) else {
        throw MXMasterServiceError.featureUnavailable(HIDPPFeatureID.adjustableDPI)
      }
      if let supportedDPIs {
        guard supportedDPIs.contains(dpi) else {
          throw MXMasterServiceError.unsupportedDPI(dpi)
        }
      } else {
        let before = try HIDPPReadOnlyProbe().readDPIOnly(channel: channel, protocolInfo: protocolInfo)
        guard before?.supported.contains(dpi) == true else {
          throw MXMasterServiceError.unsupportedDPI(dpi)
        }
      }
      _ = try channel.send(
        HIDPPMessage(
          featureIndex: index,
          functionID: 3,
          payload: [0, UInt8(dpi >> 8), UInt8(dpi & 0xFF)]
        ))
      let probe = HIDPPReadOnlyProbe()
      let dpiSnapshot = try probe.readDPIOnly(channel: channel, protocolInfo: protocolInfo)
      guard dpiSnapshot?.current == dpi else {
        throw MXMasterServiceError.verificationFailed(setting: "DPI")
      }
    }
  }

  /// Applies SmartShift mode and threshold without a redundant full state read.
  public func applySmartShift(
    mode: SmartShiftMode,
    threshold: UInt8
  ) async throws {
    guard (1...254).contains(threshold) else {
      throw MXMasterServiceError.invalidSmartShiftThreshold(threshold)
    }
    try await perform { service in
      let (channel, protocolInfo) = try service.connection()
      guard let index = protocolInfo.index(of: HIDPPFeatureID.smartShift) else {
        throw MXMasterServiceError.featureUnavailable(HIDPPFeatureID.smartShift)
      }
      _ = try channel.send(
        HIDPPMessage(
          featureIndex: index,
          functionID: 1,
          payload: [mode.rawValue, threshold, 0]
        ))
      let after = try HIDPPReadOnlyProbe().readSmartShiftOnly(
        channel: channel, protocolInfo: protocolInfo)
      guard
        after?.wheelModeCode == mode.rawValue,
        after?.autoDisengage == threshold
      else { throw MXMasterServiceError.verificationFailed(setting: "SmartShift state") }
    }
  }

  /// Applies wheel inversion without a redundant full state read.
  public func applyWheelInverted(_ inverted: Bool) async throws {
    try await perform { service in
      let (channel, protocolInfo) = try service.connection()
      guard let index = protocolInfo.index(of: HIDPPFeatureID.wheel) else {
        throw MXMasterServiceError.featureUnavailable(HIDPPFeatureID.wheel)
      }
      let current = try channel.send(HIDPPMessage(featureIndex: index, functionID: 1))
      var modeByte = current.payload[0]
      if inverted { modeByte |= 1 << 2 } else { modeByte &= ~(1 << 2) }
      _ = try channel.send(
        HIDPPMessage(featureIndex: index, functionID: 2, payload: [modeByte, 0, 0])
      )
      let after = try HIDPPReadOnlyProbe().readWheelOnly(
        channel: channel, protocolInfo: protocolInfo)
      guard after?.inverted == inverted else {
        throw MXMasterServiceError.verificationFailed(setting: "wheel direction")
      }
    }
  }

  public func configureControlCapture(
    requests: [ControlCaptureRequest],
    onEvent: @escaping @Sendable (HIDPPControlEvent) -> Void
  ) async throws {
    try await perform { service in
      if service.lastCaptureRequests == requests, service.captureSession != nil {
        return
      }
      try service.captureSession?.close()
      service.captureSession = nil
      let (channel, protocolInfo) = try service.connection()
      _ = try HIDPPControlReportingReconciler().reconcile(
        controls: MouseControl.allCases,
        channel: channel,
        protocolInfo: protocolInfo
      )
      guard !requests.isEmpty else {
        service.lastCaptureRequests = requests
        return
      }

      service.captureSession = try HIDPPControlCaptureSession(
        channel: channel,
        protocolInfo: protocolInfo,
        requests: requests,
        onEvent: onEvent
      )
      service.lastCaptureRequests = requests
    }
  }

  public func invalidate() async {
    await withCheckedContinuation { continuation in
      queue.async { [self] in
        try? captureSession?.close()
        captureSession = nil
        channel?.close()
        channel = nil
        protocolInfo = nil
        lastCaptureRequests = []
        continuation.resume()
      }
    }
  }

  /// Polls for the device until it responds or `timeout` elapses. On success the
  /// channel and protocol info are cached so the next operation reuses them.
  /// Returns `true` if the device became ready.
  public func waitForDevice(timeout: TimeInterval) async -> Bool {
    await withCheckedContinuation { continuation in
      queue.async { [self] in
        let deadline = Date(timeIntervalSinceNow: timeout)
        while Date() < deadline {
          if self.attemptConnect() {
            continuation.resume(returning: true)
            return
          }
          Thread.sleep(forTimeInterval: 0.3)
        }
        continuation.resume(returning: false)
      }
    }
  }

  /// Tries to open a channel and establish protocol info using a cached feature
  /// table when available. Returns `false` on any failure (caller should retry).
  private func attemptConnect() -> Bool {
    do {
      _ = try establishConnection()
      return true
    } catch {
      return false
    }
  }

  /// Opens a channel and establishes protocol info, reusing a cached feature
  /// table when the ping matches. On success, `channel` and `protocolInfo` are
  /// set. On failure, any partially opened channel is closed and the error is
  /// rethrown.
  private func establishConnection() throws -> (any HIDPPChannel, HIDPPProbeResult) {
    connectionGeneration &+= 1
    let generation = connectionGeneration
    let newChannel = try channelFactory { [weak self] in
      self?.deviceDidDisconnect(generation: generation)
    }
    do {
      if let cached = cachedProbeResult {
        if let ping = try? newChannel.send(
          HIDPPMessage(featureIndex: 0, functionID: 1, payload: [0, 0, 0]),
          timeout: 0.5
        ), ping.payload[0] == cached.protocolNumber {
          channel = newChannel
          protocolInfo = cached
          return (newChannel, cached)
        }
      }
      let newProtocolInfo = try HIDPPReadOnlyProbe().probeFeatures(channel: newChannel)
      cachedProbeResult = newProtocolInfo
      channel = newChannel
      protocolInfo = newProtocolInfo
      return (newChannel, newProtocolInfo)
    } catch {
      newChannel.close()
      throw error
    }
  }

  private func connection() throws -> (any HIDPPChannel, HIDPPProbeResult) {
    if let channel, let protocolInfo { return (channel, protocolInfo) }
    return try establishConnection()
  }

  private func deviceDidDisconnect(generation: UInt64) {
    queue.async { [weak self] in
      guard let self, connectionGeneration == generation else { return }
      captureSession?.abandonAfterDeviceRemoval()
      captureSession = nil
      channel?.close()
      channel = nil
      protocolInfo = nil
      lastCaptureRequests = []
      disconnectHandler()
    }
  }

  private func perform<T: Sendable>(
    _ operation: @escaping @Sendable (MXMasterDeviceService) throws -> T
  ) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
      queue.async { [self] in
        do {
          continuation.resume(returning: try operation(self))
        } catch {
          if error is HIDPPChannelError {
            try? captureSession?.close()
            captureSession = nil
            channel?.close()
            channel = nil
            protocolInfo = nil
            lastCaptureRequests = []
          }
          continuation.resume(throwing: error)
        }
      }
    }
  }
}
