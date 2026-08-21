import Foundation
import MXMasterCore

public struct ControlReportingReconciliationResult: Codable, Equatable, Sendable {
  public let normalizedControlIDs: [UInt16]
  public let finalStates: [ControlReportingState]

  public init(normalizedControlIDs: [UInt16], finalStates: [ControlReportingState]) {
    self.normalizedControlIDs = normalizedControlIDs
    self.finalStates = finalStates
  }
}

/// Removes stale, non-persistent diversion left by an interrupted software session. Persistent
/// remaps are intentionally preserved and never rewritten by this reconciler.
public struct HIDPPControlReportingReconciler {
  public init() {}

  public func run(
    controls: [MouseControl] = MouseControl.allCases
  ) throws -> ControlReportingReconciliationResult {
    let channel = try HIDPPDeviceChannel()
    defer { channel.close() }
    let protocolInfo = try HIDPPReadOnlyProbe().probeFeatures(channel: channel)
    return try reconcile(controls: controls, channel: channel, protocolInfo: protocolInfo)
  }

  public func reconcile(
    controls: [MouseControl],
    channel: any HIDPPChannel,
    protocolInfo: HIDPPProbeResult
  ) throws -> ControlReportingReconciliationResult {
    guard
      let featureIndex = protocolInfo.index(of: HIDPPFeatureID.reprogrammableControls)
    else { throw ControlCaptureError.featureUnavailable }

    var normalizedControlIDs: [UInt16] = []
    var finalStates: [ControlReportingState] = []
    let controlTable = HIDPPControlTableReader()
    for control in controls {
      let current = try controlTable.readReporting(
        controlID: control.rawValue,
        featureIndex: featureIndex,
        channel: channel
      )
      guard !current.persistentlyDiverted, current.diverted || current.rawMovement else {
        finalStates.append(current)
        continue
      }

      _ = try channel.send(
        HIDPPMessage(
          featureIndex: featureIndex,
          functionID: 3,
          payload: current.nativePassthroughPayload
        ))
      let normalized = try controlTable.readReporting(
        controlID: control.rawValue,
        featureIndex: featureIndex,
        channel: channel
      )
      guard !normalized.diverted, !normalized.rawMovement else {
        throw ControlCaptureError.restorationNotConfirmed(control.rawValue)
      }
      normalizedControlIDs.append(control.rawValue)
      finalStates.append(normalized)
    }
    return ControlReportingReconciliationResult(
      normalizedControlIDs: normalizedControlIDs,
      finalStates: finalStates
    )
  }
}
