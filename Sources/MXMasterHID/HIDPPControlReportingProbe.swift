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
      let featureIndex = protocolInfo.index(of: HIDPPFeatureID.reprogrammableControls)
    else { throw ControlCaptureError.featureUnavailable }

    return try controls.map { control in
      try HIDPPControlTableReader().readReporting(
        controlID: control.rawValue,
        featureIndex: featureIndex,
        channel: channel
      )
    }
  }
}
