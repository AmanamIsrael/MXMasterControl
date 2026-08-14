import Foundation
import MXMasterCore

/// Reads the volatile reporting state of the supported secondary controls without modifying it.
public struct HIDPPControlReportingProbe {
  public init() {}

  public func run(
    controls: [MouseControl] = MouseControl.allCases
  ) throws -> [ControlReportingState] {
    let channel = try HIDPPDeviceChannel()
    defer { channel.close() }
    let protocolInfo = try HIDPPReadOnlyProbe().probeFeatures(channel: channel)
    guard
      let featureIndex = protocolInfo.features.first(where: { $0.featureID == 0x1B04 })?
        .tableIndex
    else { throw ControlCaptureError.featureUnavailable }

    return try controls.map { control in
      let response = try channel.send(
        HIDPPMessage(
          featureIndex: featureIndex,
          functionID: 2,
          payload: [UInt8(control.rawValue >> 8), UInt8(control.rawValue & 0xFF), 0]
        ))
      return ControlReportingState(payload: response.payload)
    }
  }
}
