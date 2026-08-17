import Foundation
import MXMasterCore

public enum SettingsRoundTripError: LocalizedError, Equatable {
  case featureUnavailable(UInt16)
  case verificationFailed(setting: String)
  case operationAndRestorationFailed(operation: String, restoration: String)

  public var errorDescription: String? {
    switch self {
    case .featureUnavailable(let feature):
      String(format: "The mouse does not expose required HID++ feature 0x%04x.", feature)
    case .verificationFailed(let setting): "The mouse did not confirm the test \(setting)."
    case .operationAndRestorationFailed(let operation, let restoration):
      "The setting test failed (\(operation)) and restoration also failed (\(restoration))."
    }
  }
}

public struct HIDPPSettingsRoundTrip {
  public init() {}

  public func run() throws -> SettingsRoundTripResult {
    let channel = try HIDPPDeviceChannel()
    defer { channel.close() }
    let protocolInfo = try HIDPPReadOnlyProbe().probeFeatures(channel: channel)
    guard let smartShiftIndex = protocolInfo.index(of: HIDPPFeatureID.smartShift) else {
      throw SettingsRoundTripError.featureUnavailable(HIDPPFeatureID.smartShift)
    }
    guard let wheelIndex = protocolInfo.index(of: HIDPPFeatureID.wheel) else {
      throw SettingsRoundTripError.featureUnavailable(HIDPPFeatureID.wheel)
    }

    return SettingsRoundTripResult(
      smartShift: try testSmartShift(index: smartShiftIndex, channel: channel),
      wheel: try testWheel(index: wheelIndex, channel: channel)
    )
  }

  private func testSmartShift(
    index: UInt8,
    channel: any HIDPPChannel
  ) throws -> SmartShiftRoundTripResult {
    let original = try channel.send(HIDPPMessage(featureIndex: index, functionID: 0))
    let originalMode = original.payload[0]
    let originalThreshold = original.payload[1]
    let originalDefault = original.payload[2]
    let testThreshold = SmartShiftTestValueSelector.select(current: originalThreshold)

    do {
      _ = try channel.send(
        HIDPPMessage(
          featureIndex: index,
          functionID: 1,
          payload: [originalMode, testThreshold, 0]
        ))
      let observed = try channel.send(HIDPPMessage(featureIndex: index, functionID: 0))
      guard observed.payload[0] == originalMode, observed.payload[1] == testThreshold else {
        throw SettingsRoundTripError.verificationFailed(setting: "SmartShift threshold")
      }

      let restored = try restoreSmartShift(
        index: index,
        mode: originalMode,
        threshold: originalThreshold,
        defaultThreshold: originalDefault,
        channel: channel
      )
      return SmartShiftRoundTripResult(
        originalMode: originalMode,
        originalThreshold: originalThreshold,
        testThreshold: testThreshold,
        observedTestThreshold: observed.payload[1],
        observedRestoredMode: restored.payload[0],
        observedRestoredThreshold: restored.payload[1]
      )
    } catch {
      do {
        _ = try restoreSmartShift(
          index: index,
          mode: originalMode,
          threshold: originalThreshold,
          defaultThreshold: originalDefault,
          channel: channel
        )
      } catch let restorationError {
        throw SettingsRoundTripError.operationAndRestorationFailed(
          operation: error.localizedDescription,
          restoration: restorationError.localizedDescription
        )
      }
      throw error
    }
  }

  private func restoreSmartShift(
    index: UInt8,
    mode: UInt8,
    threshold: UInt8,
    defaultThreshold: UInt8,
    channel: any HIDPPChannel
  ) throws -> HIDPPMessage {
    _ = try channel.send(
      HIDPPMessage(
        featureIndex: index,
        functionID: 1,
        payload: [mode, threshold, defaultThreshold]
      ))
    let restored = try channel.send(HIDPPMessage(featureIndex: index, functionID: 0))
    guard restored.payload[0] == mode, restored.payload[1] == threshold else {
      throw SettingsRoundTripError.verificationFailed(setting: "SmartShift restoration")
    }
    return restored
  }

  private func testWheel(
    index: UInt8,
    channel: any HIDPPChannel
  ) throws -> WheelRoundTripResult {
    let original = try channel.send(HIDPPMessage(featureIndex: index, functionID: 1))
    let originalModeByte = original.payload[0]
    let originalInverted = originalModeByte & (1 << 2) != 0
    let testInverted = !originalInverted
    let testModeByte = originalModeByte ^ (1 << 2)

    do {
      _ = try channel.send(
        HIDPPMessage(featureIndex: index, functionID: 2, payload: [testModeByte, 0, 0])
      )
      let observed = try channel.send(HIDPPMessage(featureIndex: index, functionID: 1))
      let observedTestInverted = observed.payload[0] & (1 << 2) != 0
      guard observedTestInverted == testInverted else {
        throw SettingsRoundTripError.verificationFailed(setting: "wheel inversion")
      }

      let observedRestoredInverted = try restoreWheel(
        index: index,
        modeByte: originalModeByte,
        channel: channel
      )
      return WheelRoundTripResult(
        originalInverted: originalInverted,
        testInverted: testInverted,
        observedTestInverted: observedTestInverted,
        observedRestoredInverted: observedRestoredInverted
      )
    } catch {
      do {
        _ = try restoreWheel(index: index, modeByte: originalModeByte, channel: channel)
      } catch let restorationError {
        throw SettingsRoundTripError.operationAndRestorationFailed(
          operation: error.localizedDescription,
          restoration: restorationError.localizedDescription
        )
      }
      throw error
    }
  }

  private func restoreWheel(
    index: UInt8,
    modeByte: UInt8,
    channel: any HIDPPChannel
  ) throws -> Bool {
    _ = try channel.send(
      HIDPPMessage(featureIndex: index, functionID: 2, payload: [modeByte, 0, 0])
    )
    let restored = try channel.send(HIDPPMessage(featureIndex: index, functionID: 1))
    guard restored.payload[0] == modeByte else {
      throw SettingsRoundTripError.verificationFailed(setting: "wheel restoration")
    }
    return restored.payload[0] & (1 << 2) != 0
  }
}
