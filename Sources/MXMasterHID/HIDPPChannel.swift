import Foundation
import MXMasterCore

/// The HID++ channel seam used by every reader, probe, and round-trip in this target.
/// `HIDPPDeviceChannel` is the real implementation; tests supply scripted channels.
public protocol HIDPPChannel: AnyObject, Sendable {
  func send(_ request: HIDPPMessage, timeout: TimeInterval) throws -> HIDPPMessage
  func setEventHandler(_ handler: (@Sendable (HIDPPMessage) -> Void)?)
  func close()
}

extension HIDPPChannel {
  public func send(_ request: HIDPPMessage) throws -> HIDPPMessage {
    try send(request, timeout: 1.5)
  }
}