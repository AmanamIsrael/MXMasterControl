import Foundation

public struct ControlReportingState: Codable, Equatable, Sendable {
  public let controlID: UInt16
  public let diverted: Bool
  public let persistentlyDiverted: Bool
  public let rawMovement: Bool
  public let forceRawMovement: Bool
  public let remappedControlID: UInt16?
  public let analyticsEvents: Bool
  public let rawWheel: Bool

  public init(payload: [UInt8]) {
    precondition(payload.count >= 6)
    controlID = UInt16(payload[0]) << 8 | UInt16(payload[1])
    diverted = payload[2] & (1 << 0) != 0
    persistentlyDiverted = payload[2] & (1 << 2) != 0
    rawMovement = payload[2] & (1 << 4) != 0
    forceRawMovement = payload[2] & (1 << 6) != 0
    let remap = UInt16(payload[3]) << 8 | UInt16(payload[4])
    remappedControlID = remap == 0 ? nil : remap
    analyticsEvents = payload[5] & (1 << 0) != 0
    rawWheel = payload[5] & (1 << 2) != 0
  }

  public func temporaryDiversionPayload(rawMovement: Bool) -> [UInt8] {
    var payload = basePayload
    payload[2] |= 1 << 1
    payload[2] |= 1 << 0
    payload[2] |= 1 << 5
    if rawMovement || self.rawMovement { payload[2] |= 1 << 4 }
    return payload
  }

  public var restorationPayload: [UInt8] {
    var payload = basePayload
    payload[2] |= 1 << 1
    payload[2] |= 1 << 3
    payload[2] |= 1 << 5
    payload[2] |= 1 << 7
    if diverted { payload[2] |= 1 << 0 }
    if persistentlyDiverted { payload[2] |= 1 << 2 }
    if rawMovement { payload[2] |= 1 << 4 }
    if forceRawMovement { payload[2] |= 1 << 6 }
    payload[5] |= 1 << 1
    payload[5] |= 1 << 3
    if analyticsEvents { payload[5] |= 1 << 0 }
    if rawWheel { payload[5] |= 1 << 2 }
    return payload
  }

  private var basePayload: [UInt8] {
    var payload = Array(repeating: UInt8(0), count: 16)
    payload[0] = UInt8(controlID >> 8)
    payload[1] = UInt8(controlID & 0xFF)
    if let remappedControlID {
      payload[3] = UInt8(remappedControlID >> 8)
      payload[4] = UInt8(remappedControlID & 0xFF)
    }
    return payload
  }
}
