import Foundation
import IOKit.hid
import IOKit.hidsystem
import MXMasterCore

public enum IOHIDEnumerationError: LocalizedError, Equatable {
  case managerOpenFailed(code: Int32)

  public var errorDescription: String? {
    switch self {
    case .managerOpenFailed(let code):
      "IOHIDManager could not be opened (IOReturn \(code))."
    }
  }
}

/// Performs read-only IOHID discovery. It does not seize devices, register input callbacks,
/// send reports, or alter any mouse setting.
public struct IOHIDDeviceEnumerator {
  public init() {}

  public var listenAccess: HIDAccessStatus {
    switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
    case kIOHIDAccessTypeGranted: .granted
    case kIOHIDAccessTypeDenied: .denied
    default: .unknown
    }
  }

  /// Presents macOS's Input Monitoring request and returns the resulting process access state.
  /// This is intentionally explicit so TCC can attribute the request to the app bundle.
  public func requestListenAccess() -> HIDAccessStatus {
    _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    return listenAccess
  }

  public func enumerate(identifier: USBIdentifier? = nil) throws -> [HIDDeviceDescriptor] {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

    if let identifier {
      let matching: [String: Any] = [
        kIOHIDVendorIDKey as String: identifier.vendorID,
        kIOHIDProductIDKey as String: identifier.productID,
      ]
      IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
    } else {
      IOHIDManagerSetDeviceMatching(manager, nil)
    }

    let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    guard result == kIOReturnSuccess else {
      throw IOHIDEnumerationError.managerOpenFailed(code: result)
    }
    defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }

    guard let deviceSet = IOHIDManagerCopyDevices(manager) else { return [] }
    return (deviceSet as NSSet)
      .compactMap(Self.iohidDevice)
      .compactMap(Self.describe)
      .sorted(by: Self.sortDescriptors)
  }

  private static func iohidDevice(_ element: Any) -> IOHIDDevice? {
    guard CFGetTypeID(element as AnyObject) == IOHIDDeviceGetTypeID() else { return nil }
    return unsafeDowncast(element as AnyObject, to: IOHIDDevice.self)
  }

  private static func describe(_ device: IOHIDDevice) -> HIDDeviceDescriptor? {
    guard
      let vendorID = integerProperty(device, key: kIOHIDVendorIDKey),
      let productID = integerProperty(device, key: kIOHIDProductIDKey)
    else { return nil }

    let usagePage = integerProperty(device, key: kIOHIDPrimaryUsagePageKey)
    let usage = integerProperty(device, key: kIOHIDPrimaryUsageKey)
    let primaryUsage = usagePage.flatMap { page in
      usage.map { HIDUsage(page: page, usage: $0) }
    }

    return HIDDeviceDescriptor(
      identifier: USBIdentifier(vendorID: vendorID, productID: productID),
      productName: stringProperty(device, key: kIOHIDProductKey),
      manufacturer: stringProperty(device, key: kIOHIDManufacturerKey),
      transport: stringProperty(device, key: kIOHIDTransportKey),
      primaryUsage: primaryUsage,
      usagePairs: usagePairs(device),
      reportDescriptorByteCount: dataProperty(device, key: kIOHIDReportDescriptorKey)?.count,
      versionNumber: integerProperty(device, key: kIOHIDVersionNumberKey),
      hasSerialNumber: stringProperty(device, key: kIOHIDSerialNumberKey) != nil
    )
  }

  private static func integerProperty(_ device: IOHIDDevice, key: String) -> Int? {
    (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue
  }

  private static func stringProperty(_ device: IOHIDDevice, key: String) -> String? {
    IOHIDDeviceGetProperty(device, key as CFString) as? String
  }

  private static func dataProperty(_ device: IOHIDDevice, key: String) -> Data? {
    IOHIDDeviceGetProperty(device, key as CFString) as? Data
  }

  private static func usagePairs(_ device: IOHIDDevice) -> [HIDUsage] {
    guard
      let pairs = IOHIDDeviceGetProperty(device, kIOHIDDeviceUsagePairsKey as CFString)
        as? [[String: Any]]
    else { return [] }

    return Set(
      pairs.compactMap { pair in
        guard
          let page = (pair[kIOHIDDeviceUsagePageKey] as? NSNumber)?.intValue,
          let usage = (pair[kIOHIDDeviceUsageKey] as? NSNumber)?.intValue
        else { return nil }
        return HIDUsage(page: page, usage: usage)
      }
    )
    .sorted { lhs, rhs in
      lhs.page == rhs.page ? lhs.usage < rhs.usage : lhs.page < rhs.page
    }
  }

  private static func sortDescriptors(
    _ lhs: HIDDeviceDescriptor,
    _ rhs: HIDDeviceDescriptor
  ) -> Bool {
    let lhsUsage = lhs.primaryUsage?.hexadecimalDescription ?? ""
    let rhsUsage = rhs.primaryUsage?.hexadecimalDescription ?? ""
    if lhsUsage != rhsUsage { return lhsUsage < rhsUsage }
    return (lhs.productName ?? "") < (rhs.productName ?? "")
  }
}
