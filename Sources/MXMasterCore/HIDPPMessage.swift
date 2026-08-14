import Foundation

public struct HIDPPMessage: Equatable, Sendable {
  public static let longReportID: UInt8 = 0x11
  public static let longReportLength = 20
  public static let directDeviceIndex: UInt8 = 0xFF

  public let deviceIndex: UInt8
  public let featureIndex: UInt8
  public let functionID: UInt8
  public let softwareID: UInt8
  public let payload: [UInt8]

  public init(
    deviceIndex: UInt8 = Self.directDeviceIndex,
    featureIndex: UInt8,
    functionID: UInt8,
    softwareID: UInt8 = 1,
    payload: [UInt8] = []
  ) {
    precondition(functionID < 16, "HID++ function IDs are four bits")
    precondition(softwareID < 16, "HID++ software IDs are four bits")
    precondition(payload.count <= 16, "A long HID++ report carries at most 16 payload bytes")
    self.deviceIndex = deviceIndex
    self.featureIndex = featureIndex
    self.functionID = functionID
    self.softwareID = softwareID
    self.payload = payload + Array(repeating: 0, count: 16 - payload.count)
  }

  public var functionAndSoftwareID: UInt8 {
    (functionID << 4) | softwareID
  }

  public var encodedLongReport: [UInt8] {
    [Self.longReportID, deviceIndex, featureIndex, functionAndSoftwareID] + payload
  }

  public static func decodeLongReport(_ bytes: [UInt8]) -> HIDPPMessage? {
    guard bytes.count == longReportLength, bytes[0] == longReportID else { return nil }
    let functionAndSoftwareID = bytes[3]
    let softwareID = functionAndSoftwareID & 0x0F
    return HIDPPMessage(
      deviceIndex: bytes[1],
      featureIndex: bytes[2],
      functionID: functionAndSoftwareID >> 4,
      softwareID: softwareID,
      payload: Array(bytes[4...])
    )
  }

  public var isUnsolicitedEvent: Bool { softwareID == 0 }

  public func matchesResponse(_ bytes: [UInt8]) -> Bool {
    guard bytes.count == Self.longReportLength, bytes[0] == Self.longReportID else { return false }
    if bytes[1] != deviceIndex { return false }
    if bytes[2] == 0xFF {
      return bytes[3] == featureIndex && bytes[4] == functionAndSoftwareID
    }
    return bytes[2] == featureIndex && bytes[3] == functionAndSoftwareID
  }
}

public enum HIDPPControlEvent: Equatable, Sendable {
  case divertedButtons([UInt16])
  case rawMovement(dx: Int16, dy: Int16)

  public static func decode(_ message: HIDPPMessage, featureIndex: UInt8) -> Self? {
    guard
      message.deviceIndex == HIDPPMessage.directDeviceIndex,
      message.featureIndex == featureIndex,
      message.isUnsolicitedEvent
    else { return nil }

    switch message.functionID {
    case 0:
      let controls = stride(from: 0, to: 8, by: 2).compactMap { offset -> UInt16? in
        let value = UInt16(message.payload[offset]) << 8 | UInt16(message.payload[offset + 1])
        return value == 0 ? nil : value
      }
      return .divertedButtons(controls)
    case 1:
      let dx = Int16(bitPattern: UInt16(message.payload[0]) << 8 | UInt16(message.payload[1]))
      let dy = Int16(bitPattern: UInt16(message.payload[2]) << 8 | UInt16(message.payload[3]))
      return .rawMovement(dx: dx, dy: dy)
    default:
      return nil
    }
  }
}

public struct HIDPPFeatureDescriptor: Codable, Equatable, Sendable {
  public let tableIndex: UInt8
  public let featureID: UInt16
  public let typeFlags: UInt8
  public let version: UInt8

  public init(tableIndex: UInt8, featureID: UInt16, typeFlags: UInt8, version: UInt8) {
    self.tableIndex = tableIndex
    self.featureID = featureID
    self.typeFlags = typeFlags
    self.version = version
  }

  public var hexadecimalID: String {
    String(format: "0x%04x", featureID)
  }
}

public struct HIDPPProbeResult: Codable, Equatable, Sendable {
  public let protocolNumber: UInt8
  public let targetSoftware: UInt8
  public let features: [HIDPPFeatureDescriptor]

  public init(
    protocolNumber: UInt8,
    targetSoftware: UInt8,
    features: [HIDPPFeatureDescriptor]
  ) {
    self.protocolNumber = protocolNumber
    self.targetSoftware = targetSoftware
    self.features = features
  }
}
