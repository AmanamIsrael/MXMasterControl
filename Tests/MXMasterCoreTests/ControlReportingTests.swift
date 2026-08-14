import Testing

@testable import MXMasterCore

@Test func temporaryDiversionPreservesRemapAndRequestsOnlyTemporaryFields() {
  let original = ControlReportingState(
    payload: [0x00, 0xC3, 0x04, 0x00, 0x52, 0x01] + Array(repeating: 0, count: 10)
  )
  let payload = original.temporaryDiversionPayload(rawMovement: true)

  #expect(payload[0...1] == [0x00, 0xC3])
  #expect(payload[2] == 0b0011_0011)
  #expect(payload[3...4] == [0x00, 0x52])
  #expect(payload[5] == 0)
}

@Test func restorationPayloadCarriesEveryOriginalReportingBit() {
  let original = ControlReportingState(
    payload: [0x00, 0xC3, 0b0101_0101, 0, 0, 0b0000_0101] + Array(repeating: 0, count: 10)
  )
  let payload = original.restorationPayload

  #expect(payload[2] == 0xFF)
  #expect(payload[5] == 0x0F)
  #expect(ControlReportingState(payload: [0, 0xC3, 0x55, 0, 0, 0x05]) == original)
}

@Test func nativePassthroughClearsOnlyTemporaryDiversionValues() {
  let original = ControlReportingState(
    payload: [0x00, 0xC3, 0b0101_0101, 0x00, 0x56, 0b0000_0101]
  )
  let payload = original.nativePassthroughPayload
  let decoded = ControlReportingState(payload: payload)

  #expect(payload[2] & 0b1010_1010 == 0b1010_1010)
  #expect(!decoded.diverted)
  #expect(!decoded.rawMovement)
  #expect(decoded.persistentlyDiverted == original.persistentlyDiverted)
  #expect(decoded.forceRawMovement == original.forceRawMovement)
  #expect(decoded.remappedControlID == original.remappedControlID)
  #expect(decoded.analyticsEvents == original.analyticsEvents)
  #expect(decoded.rawWheel == original.rawWheel)
}
