import Foundation
import MXMasterCore

public struct HIDPPReadOnlyProbe {
  public init() {}

  public func run() throws -> HIDPPProbeResult {
    let channel = try HIDPPDeviceChannel()
    defer { channel.close() }
    return try probeFeatures(channel: channel)
  }

  public func readState() throws -> MXMasterReadOnlySnapshot {
    let channel = try HIDPPDeviceChannel()
    defer { channel.close() }
    let protocolInfo = try probeFeatures(channel: channel)
    return try readState(channel: channel, protocolInfo: protocolInfo)
  }

  func readState(
    channel: HIDPPDeviceChannel,
    protocolInfo: HIDPPProbeResult
  ) throws -> MXMasterReadOnlySnapshot {
    let indexByFeature = Dictionary(
      protocolInfo.features.map { ($0.featureID, $0.tableIndex) },
      uniquingKeysWith: { first, _ in first }
    )

    return MXMasterReadOnlySnapshot(
      protocolInfo: protocolInfo,
      battery: try indexByFeature[0x1000].map { try readBattery(index: $0, channel: channel) },
      dpi: try indexByFeature[0x2201].map { try readDPI(index: $0, channel: channel) },
      smartShift: try indexByFeature[0x2110].map {
        try readSmartShift(index: $0, channel: channel)
      },
      wheel: try indexByFeature[0x2121].map { try readWheel(index: $0, channel: channel) },
      thumbWheel: try indexByFeature[0x2150].map {
        try readThumbWheel(index: $0, channel: channel)
      },
      controls: try indexByFeature[0x1B04].map {
        try readControls(index: $0, channel: channel)
      } ?? []
    )
  }

  func readDPIOnly(
    channel: HIDPPDeviceChannel,
    protocolInfo: HIDPPProbeResult
  ) throws -> DPISnapshot? {
    guard let index = protocolInfo.features.first(where: { $0.featureID == 0x2201 })?.tableIndex
    else { return nil }
    return try readDPI(index: index, channel: channel)
  }

  func readSmartShiftOnly(
    channel: HIDPPDeviceChannel,
    protocolInfo: HIDPPProbeResult
  ) throws -> SmartShiftSnapshot? {
    guard let index = protocolInfo.features.first(where: { $0.featureID == 0x2110 })?.tableIndex
    else { return nil }
    return try readSmartShift(index: index, channel: channel)
  }

  func readWheelOnly(
    channel: HIDPPDeviceChannel,
    protocolInfo: HIDPPProbeResult
  ) throws -> WheelSnapshot? {
    guard let index = protocolInfo.features.first(where: { $0.featureID == 0x2121 })?.tableIndex
    else { return nil }
    return try readWheel(index: index, channel: channel)
  }

  func readBatteryOnly(
    channel: HIDPPDeviceChannel,
    protocolInfo: HIDPPProbeResult
  ) throws -> BatterySnapshot? {
    guard let index = protocolInfo.features.first(where: { $0.featureID == 0x1000 })?.tableIndex
    else { return nil }
    return try readBattery(index: index, channel: channel)
  }

  public func probeFeatures(channel: HIDPPDeviceChannel) throws -> HIDPPProbeResult {

    let ping = try channel.send(
      HIDPPMessage(featureIndex: 0, functionID: 1, payload: [0, 0, 0])
    )

    let featureSetLookup = try channel.send(
      HIDPPMessage(featureIndex: 0, functionID: 0, payload: [0x00, 0x01, 0x00])
    )
    let featureSetIndex = featureSetLookup.payload[0]
    guard featureSetIndex != 0 else { throw HIDPPChannelError.malformedResponse }

    let countResponse = try channel.send(
      HIDPPMessage(featureIndex: featureSetIndex, functionID: 0, payload: [0, 0, 0])
    )
    let count = countResponse.payload[0]

    var features: [HIDPPFeatureDescriptor] = []
    features.reserveCapacity(Int(count))
    if count > 0 {
      for tableIndex in UInt8(1)...count {
        let response = try readFeature(
          tableIndex,
          featureSetIndex: featureSetIndex,
          channel: channel
        )
        let featureID = UInt16(response.payload[0]) << 8 | UInt16(response.payload[1])
        features.append(
          HIDPPFeatureDescriptor(
            tableIndex: tableIndex,
            featureID: featureID,
            typeFlags: response.payload[2],
            version: response.payload[3]
          ))
      }
    }

    return HIDPPProbeResult(
      protocolNumber: ping.payload[0],
      targetSoftware: ping.payload[1],
      features: features
    )
  }

  private func readBattery(index: UInt8, channel: HIDPPDeviceChannel) throws -> BatterySnapshot {
    let response = try channel.send(HIDPPMessage(featureIndex: index, functionID: 0))
    return BatterySnapshot(
      percentage: response.payload[0],
      nextReportedPercentage: response.payload[1],
      statusCode: response.payload[2]
    )
  }

  private func readDPI(index: UInt8, channel: HIDPPDeviceChannel) throws -> DPISnapshot {
    let count = try channel.send(HIDPPMessage(featureIndex: index, functionID: 0)).payload[0]
    let supportedResponse = try channel.send(
      HIDPPMessage(featureIndex: index, functionID: 1, payload: [0, 0, 0])
    )
    let currentResponse = try channel.send(
      HIDPPMessage(featureIndex: index, functionID: 2, payload: [0, 0, 0])
    )
    return try DPISnapshot(
      sensorCount: count,
      current: UInt16(currentResponse.payload[1]) << 8 | UInt16(currentResponse.payload[2]),
      supported: DPIListParser.parse(supportedResponse.payload[1...])
    )
  }

  private func readSmartShift(
    index: UInt8,
    channel: HIDPPDeviceChannel
  ) throws -> SmartShiftSnapshot {
    let response = try channel.send(HIDPPMessage(featureIndex: index, functionID: 0))
    return SmartShiftSnapshot(
      wheelModeCode: response.payload[0],
      autoDisengage: response.payload[1],
      defaultAutoDisengage: response.payload[2]
    )
  }

  private func readWheel(index: UInt8, channel: HIDPPDeviceChannel) throws -> WheelSnapshot {
    let capabilities = try channel.send(HIDPPMessage(featureIndex: index, functionID: 0))
    let mode = try channel.send(HIDPPMessage(featureIndex: index, functionID: 1))
    let ratchet = try channel.send(HIDPPMessage(featureIndex: index, functionID: 3))
    return WheelSnapshot(
      multiplier: capabilities.payload[0],
      supportsInversion: capabilities.payload[1] & (1 << 3) != 0,
      hasRatchetSwitch: capabilities.payload[1] & (1 << 2) != 0,
      ratchetsPerRotation: capabilities.payload[2],
      diameterMillimeters: capabilities.payload[3],
      inverted: mode.payload[0] & (1 << 2) != 0,
      highResolution: mode.payload[0] & (1 << 1) != 0,
      diverted: mode.payload[0] & 1 != 0,
      ratchetStateCode: ratchet.payload[0] & 1
    )
  }

  private func readThumbWheel(
    index: UInt8,
    channel: HIDPPDeviceChannel
  ) throws -> ThumbWheelSnapshot {
    let info = try channel.send(HIDPPMessage(featureIndex: index, functionID: 0))
    let status = try channel.send(HIDPPMessage(featureIndex: index, functionID: 1))
    return ThumbWheelSnapshot(
      nativeResolution: UInt16(info.payload[0]) << 8 | UInt16(info.payload[1]),
      divertedResolution: UInt16(info.payload[2]) << 8 | UInt16(info.payload[3]),
      timeUnitMicroseconds: UInt16(info.payload[6]) << 8 | UInt16(info.payload[7]),
      defaultDirectionCode: info.payload[4] & 1,
      capabilityFlags: info.payload[5],
      diverted: status.payload[0] == 1,
      directionInverted: status.payload[1] & 1 != 0,
      touchActive: status.payload[1] & (1 << 1) != 0,
      proximityActive: status.payload[1] & (1 << 2) != 0
    )
  }

  private func readControls(
    index: UInt8,
    channel: HIDPPDeviceChannel
  ) throws -> [ControlSnapshot] {
    let count = try channel.send(HIDPPMessage(featureIndex: index, functionID: 0)).payload[0]
    guard count > 0 else { return [] }
    return try (UInt8(0)..<count).map { row in
      let response = try channel.send(
        HIDPPMessage(featureIndex: index, functionID: 1, payload: [row])
      )
      return ControlSnapshot(
        controlID: UInt16(response.payload[0]) << 8 | UInt16(response.payload[1]),
        defaultTaskID: UInt16(response.payload[2]) << 8 | UInt16(response.payload[3]),
        flags: UInt16(response.payload[4]) | UInt16(response.payload[8]) << 8,
        position: response.payload[5],
        group: response.payload[6],
        groupMask: response.payload[7]
      )
    }
  }

  private func readFeature(
    _ tableIndex: UInt8,
    featureSetIndex: UInt8,
    channel: HIDPPDeviceChannel
  ) throws -> HIDPPMessage {
    var lastError: Error?
    for attempt in 1...3 {
      do {
        return try channel.send(
          HIDPPMessage(
            featureIndex: featureSetIndex,
            functionID: 1,
            payload: [tableIndex, 0, 0]
          ),
          timeout: 0.8
        )
      } catch {
        lastError = error
        if attempt < 3 { Thread.sleep(forTimeInterval: 0.12) }
      }
    }
    throw lastError ?? HIDPPChannelError.responseTimedOut
  }
}
