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
  private var channel: HIDPPDeviceChannel?
  private var protocolInfo: HIDPPProbeResult?

  public init() {}

  deinit {
    channel?.close()
  }

  public func readState() async throws -> MXMasterReadOnlySnapshot {
    try await perform { service in
      let (channel, protocolInfo) = try service.connection()
      return try HIDPPReadOnlyProbe().readState(channel: channel, protocolInfo: protocolInfo)
    }
  }

  public func setDPI(_ dpi: UInt16) async throws -> MXMasterReadOnlySnapshot {
    try await perform { service in
      let (channel, protocolInfo) = try service.connection()
      guard let index = service.index(of: 0x2201, in: protocolInfo) else {
        throw MXMasterServiceError.featureUnavailable(0x2201)
      }
      let before = try HIDPPReadOnlyProbe().readState(channel: channel, protocolInfo: protocolInfo)
      guard before.dpi?.supported.contains(dpi) == true else {
        throw MXMasterServiceError.unsupportedDPI(dpi)
      }
      _ = try channel.send(
        HIDPPMessage(
          featureIndex: index,
          functionID: 3,
          payload: [0, UInt8(dpi >> 8), UInt8(dpi & 0xFF)]
        ))
      let after = try HIDPPReadOnlyProbe().readState(channel: channel, protocolInfo: protocolInfo)
      guard after.dpi?.current == dpi else {
        throw MXMasterServiceError.verificationFailed(setting: "DPI")
      }
      return after
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
      guard let index = service.index(of: 0x2110, in: protocolInfo) else {
        throw MXMasterServiceError.featureUnavailable(0x2110)
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
      guard let index = service.index(of: 0x2121, in: protocolInfo) else {
        throw MXMasterServiceError.featureUnavailable(0x2121)
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

  public func invalidate() async {
    await withCheckedContinuation { continuation in
      queue.async { [self] in
        channel?.close()
        channel = nil
        protocolInfo = nil
        continuation.resume()
      }
    }
  }

  private func connection() throws -> (HIDPPDeviceChannel, HIDPPProbeResult) {
    if let channel, let protocolInfo { return (channel, protocolInfo) }
    let newChannel = try HIDPPDeviceChannel()
    do {
      let newProtocolInfo = try HIDPPReadOnlyProbe().probeFeatures(channel: newChannel)
      channel = newChannel
      protocolInfo = newProtocolInfo
      return (newChannel, newProtocolInfo)
    } catch {
      newChannel.close()
      throw error
    }
  }

  private func index(of featureID: UInt16, in info: HIDPPProbeResult) -> UInt8? {
    info.features.first(where: { $0.featureID == featureID })?.tableIndex
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
            channel?.close()
            channel = nil
            protocolInfo = nil
          }
          continuation.resume(throwing: error)
        }
      }
    }
  }
}
