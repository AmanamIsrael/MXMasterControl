import Foundation
import MXMasterCore

/// Reads the reprogrammable-controls feature (0x1B04) through one HID++ channel.
/// The single home for control-table wire traffic so the read-only probe, capture
/// session, reconciler, and reporting probe cannot drift apart.
public struct HIDPPControlTableReader {
  public init() {}

  public func readControls(
    featureIndex: UInt8,
    channel: any HIDPPChannel
  ) throws -> [ControlSnapshot] {
    let count = try channel.send(HIDPPMessage(featureIndex: featureIndex, functionID: 0)).payload[0]
    guard count > 0 else { return [] }
    return try (UInt8(0)..<count).map { row in
      let response = try channel.send(
        HIDPPMessage(featureIndex: featureIndex, functionID: 1, payload: [row])
      )
      return ControlSnapshot(payload: response.payload)
    }
  }

  public func readReporting(
    controlID: UInt16,
    featureIndex: UInt8,
    channel: any HIDPPChannel
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