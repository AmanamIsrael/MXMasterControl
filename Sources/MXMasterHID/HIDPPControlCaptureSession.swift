import Foundation
import MXMasterCore

public enum ControlCaptureError: LocalizedError, Equatable {
  case featureUnavailable
  case controlUnavailable(UInt16)
  case controlNotDivertable(UInt16)
  case armingNotConfirmed(UInt16)
  case restorationNotConfirmed(UInt16)

  public var errorDescription: String? {
    switch self {
    case .featureUnavailable: "The mouse does not expose Reprogrammable Controls (0x1b04)."
    case .controlUnavailable(let control):
      String(format: "Control 0x%04x is not present on this mouse.", control)
    case .controlNotDivertable(let control):
      String(format: "Control 0x%04x cannot be temporarily diverted.", control)
    case .armingNotConfirmed(let control):
      String(format: "Temporary diversion was not confirmed for control 0x%04x.", control)
    case .restorationNotConfirmed(let control):
      String(format: "Original reporting state was not restored for control 0x%04x.", control)
    }
  }
}

/// Captures one HID++ control without making persistent firmware changes. The original reporting
/// state is read before arming and restored on `close()` and deinitialization.
public final class HIDPPControlCaptureSession: @unchecked Sendable {
  private let channel: HIDPPDeviceChannel
  private let featureIndex: UInt8
  private let controlID: UInt16
  private let originalState: ControlReportingState
  private let closeLock = NSLock()
  private var isClosed = false

  public init(
    controlID: UInt16,
    rawMovement: Bool,
    onEvent: @escaping @Sendable (HIDPPControlEvent) -> Void
  ) throws {
    let channel = try HIDPPDeviceChannel()
    self.channel = channel
    self.controlID = controlID

    do {
      let protocolInfo = try HIDPPReadOnlyProbe().probeFeatures(channel: channel)
      guard
        let featureIndex = protocolInfo.features.first(where: { $0.featureID == 0x1B04 })?
          .tableIndex
      else { throw ControlCaptureError.featureUnavailable }
      self.featureIndex = featureIndex

      let controls = try Self.readControls(featureIndex: featureIndex, channel: channel)
      guard let control = controls.first(where: { $0.controlID == controlID }) else {
        throw ControlCaptureError.controlUnavailable(controlID)
      }
      guard control.flags & (1 << 5) != 0 else {
        throw ControlCaptureError.controlNotDivertable(controlID)
      }

      let originalState = try Self.readReporting(
        controlID: controlID,
        featureIndex: featureIndex,
        channel: channel
      )
      self.originalState = originalState

      _ = try channel.send(
        HIDPPMessage(
          featureIndex: featureIndex,
          functionID: 3,
          payload: originalState.temporaryDiversionPayload(rawMovement: rawMovement)
        ))
      let armed = try Self.readReporting(
        controlID: controlID,
        featureIndex: featureIndex,
        channel: channel
      )
      guard armed.diverted, !rawMovement || armed.rawMovement else {
        throw ControlCaptureError.armingNotConfirmed(controlID)
      }

      channel.setEventHandler { message in
        guard let event = HIDPPControlEvent.decode(message, featureIndex: featureIndex) else {
          return
        }
        onEvent(event)
      }
    } catch {
      channel.close()
      throw error
    }
  }

  deinit {
    try? close()
  }

  public func close() throws {
    closeLock.lock()
    guard !isClosed else {
      closeLock.unlock()
      return
    }
    isClosed = true
    closeLock.unlock()

    channel.setEventHandler(nil)
    defer { channel.close() }
    _ = try channel.send(
      HIDPPMessage(
        featureIndex: featureIndex,
        functionID: 3,
        payload: originalState.restorationPayload
      ))
    let restored = try Self.readReporting(
      controlID: controlID,
      featureIndex: featureIndex,
      channel: channel
    )
    guard restored == originalState else {
      throw ControlCaptureError.restorationNotConfirmed(controlID)
    }
  }

  private static func readControls(
    featureIndex: UInt8,
    channel: HIDPPDeviceChannel
  ) throws -> [ControlSnapshot] {
    let count = try channel.send(HIDPPMessage(featureIndex: featureIndex, functionID: 0)).payload[0]
    guard count > 0 else { return [] }
    return try (UInt8(0)..<count).map { row in
      let response = try channel.send(
        HIDPPMessage(featureIndex: featureIndex, functionID: 1, payload: [row])
      )
      return ControlSnapshot(
        controlID: UInt16(response.payload[0]) << 8 | UInt16(response.payload[1]),
        defaultTaskID: UInt16(response.payload[2]) << 8 | UInt16(response.payload[3]),
        flags: UInt16(response.payload[4]) | UInt16(response.payload[8]) << 8,
        position: response.payload[5],
        group: response.payload[6],
        groupMask: response.payload[7]
      )
    }
  }

  private static func readReporting(
    controlID: UInt16,
    featureIndex: UInt8,
    channel: HIDPPDeviceChannel
  ) throws -> ControlReportingState {
    let response = try channel.send(
      HIDPPMessage(
        featureIndex: featureIndex,
        functionID: 2,
        payload: [UInt8(controlID >> 8), UInt8(controlID & 0xFF), 0]
      ))
    return ControlReportingState(payload: response.payload)
  }
}
