import Testing

@testable import MXMasterCore

@Test func dpiListParserExpandsRangeMarkers() throws {
  let payload: [UInt8] = [0x01, 0x90, 0xE1, 0x90, 0x06, 0x40, 0x00, 0x00]
  #expect(try DPIListParser.parse(payload[...]) == [400, 800, 1200, 1600])
}

@Test func dpiListParserRejectsLeadingRangeMarker() {
  let payload: [UInt8] = [0xE0, 0x32, 0x1F, 0x40]
  #expect(throws: DPIListParser.ParseError.malformedRange) {
    try DPIListParser.parse(payload[...])
  }
}

@Test func dpiTestValuePrefersTheNextHigherSupportedValue() {
  #expect(DPITestValueSelector.select(current: 1000, supported: [950, 1000, 1050]) == 1050)
  #expect(DPITestValueSelector.select(current: 1050, supported: [950, 1000, 1050]) == 1000)
  #expect(DPITestValueSelector.select(current: 1000, supported: [1000]) == nil)
}

@Test func smartShiftTestValueStaysInsideWritableRange() {
  #expect(SmartShiftTestValueSelector.select(current: 10) == 11)
  #expect(SmartShiftTestValueSelector.select(current: 0) == 1)
  #expect(SmartShiftTestValueSelector.select(current: 254) == 253)
  #expect(SmartShiftTestValueSelector.select(current: 255) == 253)
}
