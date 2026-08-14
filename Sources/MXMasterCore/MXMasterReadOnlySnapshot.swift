import Foundation

public struct MXMasterReadOnlySnapshot: Codable, Equatable, Sendable {
  public let protocolInfo: HIDPPProbeResult
  public let battery: BatterySnapshot?
  public let dpi: DPISnapshot?
  public let smartShift: SmartShiftSnapshot?
  public let wheel: WheelSnapshot?
  public let thumbWheel: ThumbWheelSnapshot?
  public let controls: [ControlSnapshot]

  public init(
    protocolInfo: HIDPPProbeResult,
    battery: BatterySnapshot?,
    dpi: DPISnapshot?,
    smartShift: SmartShiftSnapshot?,
    wheel: WheelSnapshot?,
    thumbWheel: ThumbWheelSnapshot?,
    controls: [ControlSnapshot]
  ) {
    self.protocolInfo = protocolInfo
    self.battery = battery
    self.dpi = dpi
    self.smartShift = smartShift
    self.wheel = wheel
    self.thumbWheel = thumbWheel
    self.controls = controls
  }
}

public struct BatterySnapshot: Codable, Equatable, Sendable {
  public let percentage: UInt8
  public let nextReportedPercentage: UInt8
  public let statusCode: UInt8

  public init(percentage: UInt8, nextReportedPercentage: UInt8, statusCode: UInt8) {
    self.percentage = percentage
    self.nextReportedPercentage = nextReportedPercentage
    self.statusCode = statusCode
  }
}

public struct DPISnapshot: Codable, Equatable, Sendable {
  public let sensorCount: UInt8
  public let current: UInt16
  public let supported: [UInt16]

  public init(sensorCount: UInt8, current: UInt16, supported: [UInt16]) {
    self.sensorCount = sensorCount
    self.current = current
    self.supported = supported
  }
}

public struct SmartShiftSnapshot: Codable, Equatable, Sendable {
  public let wheelModeCode: UInt8
  public let autoDisengage: UInt8
  public let defaultAutoDisengage: UInt8

  public init(wheelModeCode: UInt8, autoDisengage: UInt8, defaultAutoDisengage: UInt8) {
    self.wheelModeCode = wheelModeCode
    self.autoDisengage = autoDisengage
    self.defaultAutoDisengage = defaultAutoDisengage
  }
}

public struct WheelSnapshot: Codable, Equatable, Sendable {
  public let multiplier: UInt8
  public let supportsInversion: Bool
  public let hasRatchetSwitch: Bool
  public let ratchetsPerRotation: UInt8
  public let diameterMillimeters: UInt8
  public let inverted: Bool
  public let highResolution: Bool
  public let diverted: Bool
  public let ratchetStateCode: UInt8

  public init(
    multiplier: UInt8,
    supportsInversion: Bool,
    hasRatchetSwitch: Bool,
    ratchetsPerRotation: UInt8,
    diameterMillimeters: UInt8,
    inverted: Bool,
    highResolution: Bool,
    diverted: Bool,
    ratchetStateCode: UInt8
  ) {
    self.multiplier = multiplier
    self.supportsInversion = supportsInversion
    self.hasRatchetSwitch = hasRatchetSwitch
    self.ratchetsPerRotation = ratchetsPerRotation
    self.diameterMillimeters = diameterMillimeters
    self.inverted = inverted
    self.highResolution = highResolution
    self.diverted = diverted
    self.ratchetStateCode = ratchetStateCode
  }
}

public struct ThumbWheelSnapshot: Codable, Equatable, Sendable {
  public let nativeResolution: UInt16
  public let divertedResolution: UInt16
  public let timeUnitMicroseconds: UInt16
  public let defaultDirectionCode: UInt8
  public let capabilityFlags: UInt8
  public let diverted: Bool
  public let directionInverted: Bool
  public let touchActive: Bool
  public let proximityActive: Bool

  public init(
    nativeResolution: UInt16,
    divertedResolution: UInt16,
    timeUnitMicroseconds: UInt16,
    defaultDirectionCode: UInt8,
    capabilityFlags: UInt8,
    diverted: Bool,
    directionInverted: Bool,
    touchActive: Bool,
    proximityActive: Bool
  ) {
    self.nativeResolution = nativeResolution
    self.divertedResolution = divertedResolution
    self.timeUnitMicroseconds = timeUnitMicroseconds
    self.defaultDirectionCode = defaultDirectionCode
    self.capabilityFlags = capabilityFlags
    self.diverted = diverted
    self.directionInverted = directionInverted
    self.touchActive = touchActive
    self.proximityActive = proximityActive
  }
}

public struct ControlSnapshot: Codable, Equatable, Sendable {
  public let controlID: UInt16
  public let defaultTaskID: UInt16
  public let flags: UInt16
  public let position: UInt8
  public let group: UInt8
  public let groupMask: UInt8

  public init(
    controlID: UInt16,
    defaultTaskID: UInt16,
    flags: UInt16,
    position: UInt8,
    group: UInt8,
    groupMask: UInt8
  ) {
    self.controlID = controlID
    self.defaultTaskID = defaultTaskID
    self.flags = flags
    self.position = position
    self.group = group
    self.groupMask = groupMask
  }
}

public enum DPIListParser {
  public enum ParseError: Error, Equatable {
    case malformedRange
    case noValues
  }

  public static func parse(_ bytes: ArraySlice<UInt8>) throws -> [UInt16] {
    let bytes = Array(bytes)
    var values: [UInt16] = []
    var offset = 0

    while offset + 1 < bytes.count {
      let value = UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
      if value == 0 { break }

      if value >> 13 == 0b111 {
        let step = value & 0x1FFF
        guard step != 0, offset + 3 < bytes.count, let startValue = values.last else {
          throw ParseError.malformedRange
        }
        let end = UInt16(bytes[offset + 2]) << 8 | UInt16(bytes[offset + 3])
        guard end >= startValue else { throw ParseError.malformedRange }
        var next = UInt32(startValue) + UInt32(step)
        while next < UInt32(end) {
          guard next <= UInt32(UInt16.max) else { throw ParseError.malformedRange }
          values.append(UInt16(next))
          next += UInt32(step)
        }
        values.append(end)
        offset += 4
      } else {
        values.append(value)
        offset += 2
      }
    }

    guard !values.isEmpty else { throw ParseError.noValues }
    return Array(Set(values)).sorted()
  }
}

public struct DPIRoundTripResult: Codable, Equatable, Sendable {
  public let original: UInt16
  public let testValue: UInt16
  public let observedTestValue: UInt16
  public let observedRestoredValue: UInt16

  public init(
    original: UInt16,
    testValue: UInt16,
    observedTestValue: UInt16,
    observedRestoredValue: UInt16
  ) {
    self.original = original
    self.testValue = testValue
    self.observedTestValue = observedTestValue
    self.observedRestoredValue = observedRestoredValue
  }

  public var testConfirmed: Bool { observedTestValue == testValue }
  public var restorationConfirmed: Bool { observedRestoredValue == original }
}

public enum DPITestValueSelector {
  public static func select(current: UInt16, supported: [UInt16]) -> UInt16? {
    supported.first(where: { $0 > current }) ?? supported.last(where: { $0 < current })
  }
}

public struct SmartShiftRoundTripResult: Codable, Equatable, Sendable {
  public let originalMode: UInt8
  public let originalThreshold: UInt8
  public let testThreshold: UInt8
  public let observedTestThreshold: UInt8
  public let observedRestoredMode: UInt8
  public let observedRestoredThreshold: UInt8

  public init(
    originalMode: UInt8,
    originalThreshold: UInt8,
    testThreshold: UInt8,
    observedTestThreshold: UInt8,
    observedRestoredMode: UInt8,
    observedRestoredThreshold: UInt8
  ) {
    self.originalMode = originalMode
    self.originalThreshold = originalThreshold
    self.testThreshold = testThreshold
    self.observedTestThreshold = observedTestThreshold
    self.observedRestoredMode = observedRestoredMode
    self.observedRestoredThreshold = observedRestoredThreshold
  }
}

public struct WheelRoundTripResult: Codable, Equatable, Sendable {
  public let originalInverted: Bool
  public let testInverted: Bool
  public let observedTestInverted: Bool
  public let observedRestoredInverted: Bool

  public init(
    originalInverted: Bool,
    testInverted: Bool,
    observedTestInverted: Bool,
    observedRestoredInverted: Bool
  ) {
    self.originalInverted = originalInverted
    self.testInverted = testInverted
    self.observedTestInverted = observedTestInverted
    self.observedRestoredInverted = observedRestoredInverted
  }
}

public struct SettingsRoundTripResult: Codable, Equatable, Sendable {
  public let smartShift: SmartShiftRoundTripResult
  public let wheel: WheelRoundTripResult

  public init(smartShift: SmartShiftRoundTripResult, wheel: WheelRoundTripResult) {
    self.smartShift = smartShift
    self.wheel = wheel
  }
}

public enum SmartShiftTestValueSelector {
  public static func select(current: UInt8) -> UInt8 {
    current >= 254 ? 253 : max(1, current + 1)
  }
}
