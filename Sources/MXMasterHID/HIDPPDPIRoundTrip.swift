import Foundation
import MXMasterCore

public enum DPIRoundTripError: LocalizedError, Equatable {
  case featureUnavailable
  case noAlternativeValue
  case testValueNotConfirmed(expected: UInt16, observed: UInt16)
  case restorationNotConfirmed(expected: UInt16, observed: UInt16)
  case operationFailedAndRestorationFailed(operation: String, restoration: String)

  public var errorDescription: String? {
    switch self {
    case .featureUnavailable: "The mouse does not expose Adjustable DPI (0x2201)."
    case .noAlternativeValue: "The mouse reported no safe alternative DPI value."
    case .testValueNotConfirmed(let expected, let observed):
      "DPI test write was not confirmed (expected \(expected), observed \(observed))."
    case .restorationNotConfirmed(let expected, let observed):
      "Original DPI was not restored (expected \(expected), observed \(observed))."
    case .operationFailedAndRestorationFailed(let operation, let restoration):
      "DPI test failed (\(operation)) and restoration also failed (\(restoration))."
    }
  }
}

public struct HIDPPDPIRoundTrip {
  public init() {}

  public func run() throws -> DPIRoundTripResult {
    let channel = try HIDPPDeviceChannel()
    defer { channel.close() }
    let protocolInfo = try HIDPPReadOnlyProbe().probeFeatures(channel: channel)
    guard let dpiIndex = protocolInfo.features.first(where: { $0.featureID == 0x2201 })?.tableIndex
    else { throw DPIRoundTripError.featureUnavailable }

    let original = try readCurrent(index: dpiIndex, channel: channel)
    let supported = try readSupported(index: dpiIndex, channel: channel)
    guard let testValue = DPITestValueSelector.select(current: original, supported: supported)
    else { throw DPIRoundTripError.noAlternativeValue }

    do {
      try set(testValue, index: dpiIndex, channel: channel)
      let observedTestValue = try readCurrent(index: dpiIndex, channel: channel)
      guard observedTestValue == testValue else {
        throw DPIRoundTripError.testValueNotConfirmed(
          expected: testValue,
          observed: observedTestValue
        )
      }

      try set(original, index: dpiIndex, channel: channel)
      let observedRestoredValue = try readCurrent(index: dpiIndex, channel: channel)
      guard observedRestoredValue == original else {
        throw DPIRoundTripError.restorationNotConfirmed(
          expected: original,
          observed: observedRestoredValue
        )
      }

      return DPIRoundTripResult(
        original: original,
        testValue: testValue,
        observedTestValue: observedTestValue,
        observedRestoredValue: observedRestoredValue
      )
    } catch {
      do {
        try set(original, index: dpiIndex, channel: channel)
        let restored = try readCurrent(index: dpiIndex, channel: channel)
        guard restored == original else {
          throw DPIRoundTripError.restorationNotConfirmed(expected: original, observed: restored)
        }
      } catch let restorationError {
        throw DPIRoundTripError.operationFailedAndRestorationFailed(
          operation: error.localizedDescription,
          restoration: restorationError.localizedDescription
        )
      }
      throw error
    }
  }

  private func readCurrent(index: UInt8, channel: HIDPPDeviceChannel) throws -> UInt16 {
    let response = try channel.send(
      HIDPPMessage(featureIndex: index, functionID: 2, payload: [0, 0, 0])
    )
    return UInt16(response.payload[1]) << 8 | UInt16(response.payload[2])
  }

  private func readSupported(index: UInt8, channel: HIDPPDeviceChannel) throws -> [UInt16] {
    let response = try channel.send(
      HIDPPMessage(featureIndex: index, functionID: 1, payload: [0, 0, 0])
    )
    return try DPIListParser.parse(response.payload[1...])
  }

  private func set(_ dpi: UInt16, index: UInt8, channel: HIDPPDeviceChannel) throws {
    let high = UInt8(dpi >> 8)
    let low = UInt8(dpi & 0xFF)
    _ = try channel.send(
      HIDPPMessage(featureIndex: index, functionID: 3, payload: [0, high, low])
    )
  }
}
