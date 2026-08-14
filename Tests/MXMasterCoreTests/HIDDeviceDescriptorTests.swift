import Foundation
import Testing

@testable import MXMasterCore

@Test func targetIdentifierUsesConnectedMXMaster3Product() {
  #expect(HIDDeviceDescriptor.targetIdentifier.vendorID == 0x046D)
  #expect(HIDDeviceDescriptor.targetIdentifier.productID == 0xB023)
  #expect(HIDDeviceDescriptor.targetIdentifier.hexadecimalDescription == "046d:b023")
}

@Test func diagnosticReportFindsTargetWithoutSerializingADeviceSerial() throws {
  let descriptor = HIDDeviceDescriptor(
    identifier: HIDDeviceDescriptor.targetIdentifier,
    productName: "MX Master 3",
    manufacturer: "Logitech",
    transport: "Bluetooth Low Energy",
    primaryUsage: HIDUsage(page: 1, usage: 2),
    usagePairs: [HIDUsage(page: 1, usage: 2), HIDUsage(page: 0xFF43, usage: 0x0202)],
    reportDescriptorByteCount: 123,
    versionNumber: 1,
    hasSerialNumber: true
  )
  let report = HIDDiagnosticReport(
    generatedAt: Date(timeIntervalSince1970: 0),
    listenAccess: .granted,
    matchingDevices: [descriptor]
  )

  #expect(report.foundTarget)
  #expect(report.listenAccess == .granted)
  #expect(descriptor.primaryUsage?.hexadecimalDescription == "0x0001:0x0002")
  #expect(descriptor.usagePairs.last?.hexadecimalDescription == "0xff43:0x0202")

  let json = String(decoding: try JSONEncoder().encode(report), as: UTF8.self)
  #expect(!json.contains("\"serialNumber\":"))
  #expect(json.contains("hasSerialNumber"))
}
