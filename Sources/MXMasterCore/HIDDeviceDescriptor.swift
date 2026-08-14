import Foundation

public struct USBIdentifier: Codable, Equatable, Hashable, Sendable {
  public let vendorID: Int
  public let productID: Int

  public init(vendorID: Int, productID: Int) {
    self.vendorID = vendorID
    self.productID = productID
  }

  public var hexadecimalDescription: String {
    String(format: "%04x:%04x", vendorID, productID)
  }
}

public struct HIDUsage: Codable, Equatable, Hashable, Sendable {
  public let page: Int
  public let usage: Int

  public init(page: Int, usage: Int) {
    self.page = page
    self.usage = usage
  }

  public var hexadecimalDescription: String {
    String(format: "0x%04x:0x%04x", page, usage)
  }
}

public struct HIDDeviceDescriptor: Codable, Equatable, Sendable {
  public static let targetIdentifier = USBIdentifier(vendorID: 0x046D, productID: 0xB023)

  public let identifier: USBIdentifier
  public let productName: String?
  public let manufacturer: String?
  public let transport: String?
  public let primaryUsage: HIDUsage?
  public let usagePairs: [HIDUsage]
  public let reportDescriptorByteCount: Int?
  public let versionNumber: Int?
  public let hasSerialNumber: Bool

  public init(
    identifier: USBIdentifier,
    productName: String?,
    manufacturer: String?,
    transport: String?,
    primaryUsage: HIDUsage?,
    usagePairs: [HIDUsage],
    reportDescriptorByteCount: Int?,
    versionNumber: Int?,
    hasSerialNumber: Bool
  ) {
    self.identifier = identifier
    self.productName = productName
    self.manufacturer = manufacturer
    self.transport = transport
    self.primaryUsage = primaryUsage
    self.usagePairs = usagePairs
    self.reportDescriptorByteCount = reportDescriptorByteCount
    self.versionNumber = versionNumber
    self.hasSerialNumber = hasSerialNumber
  }

  public var isTargetMXMaster3: Bool {
    identifier == Self.targetIdentifier
  }
}

public enum HIDAccessStatus: String, Codable, Equatable, Sendable {
  case granted
  case denied
  case unknown
}

public struct HIDDiagnosticReport: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let generatedAt: Date
  public let targetIdentifier: USBIdentifier
  public let listenAccess: HIDAccessStatus
  public let matchingDevices: [HIDDeviceDescriptor]

  public init(
    schemaVersion: Int = 1,
    generatedAt: Date = Date(),
    targetIdentifier: USBIdentifier = HIDDeviceDescriptor.targetIdentifier,
    listenAccess: HIDAccessStatus = .unknown,
    matchingDevices: [HIDDeviceDescriptor]
  ) {
    self.schemaVersion = schemaVersion
    self.generatedAt = generatedAt
    self.targetIdentifier = targetIdentifier
    self.listenAccess = listenAccess
    self.matchingDevices = matchingDevices
  }

  public var foundTarget: Bool {
    matchingDevices.contains(where: \.isTargetMXMaster3)
  }
}
