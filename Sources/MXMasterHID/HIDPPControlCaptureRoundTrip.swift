import Foundation
import MXMasterCore

public struct ControlCaptureRoundTripResult: Codable, Equatable, Sendable {
  public let controlIDs: [UInt16]
  public let restorationConfirmed: Bool

  public init(controlIDs: [UInt16], restorationConfirmed: Bool) {
    self.controlIDs = controlIDs
    self.restorationConfirmed = restorationConfirmed
  }
}

public struct HIDPPControlCaptureRoundTrip {
  public init() {}

  public func run() throws -> ControlCaptureRoundTripResult {
    let requests = [
      ControlCaptureRequest(controlID: MouseControl.back.rawValue, rawMovement: false),
      ControlCaptureRequest(controlID: MouseControl.forward.rawValue, rawMovement: false),
      ControlCaptureRequest(controlID: MouseControl.gesture.rawValue, rawMovement: true),
      ControlCaptureRequest(controlID: MouseControl.smartShift.rawValue, rawMovement: false),
    ]

    let channel = try HIDPPDeviceChannel()
    defer { channel.close() }
    let protocolInfo = try HIDPPReadOnlyProbe().probeFeatures(channel: channel)
    let session = try HIDPPControlCaptureSession(
      channel: channel,
      protocolInfo: protocolInfo,
      requests: requests,
      onEvent: { _ in }
    )
    try session.close()
    return ControlCaptureRoundTripResult(
      controlIDs: requests.map(\.controlID),
      restorationConfirmed: true
    )
  }
}
