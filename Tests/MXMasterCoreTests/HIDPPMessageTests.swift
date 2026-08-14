import Testing

@testable import MXMasterCore

@Test func longMessageEncodingAndDecodingRoundTrips() throws {
  let request = HIDPPMessage(
    featureIndex: 0,
    functionID: 1,
    softwareID: 3,
    payload: [0, 0, 0x5A]
  )

  #expect(request.encodedLongReport.count == 20)
  #expect(request.encodedLongReport.prefix(4) == [0x11, 0xFF, 0x00, 0x13])

  let decoded = try #require(HIDPPMessage.decodeLongReport(request.encodedLongReport))
  #expect(decoded == request)
}

@Test func responseMatchingAcceptsNormalAndDeviceErrorFrames() {
  let request = HIDPPMessage(featureIndex: 4, functionID: 2, softwareID: 1)
  var normal = request.encodedLongReport
  normal[4] = 0xAA

  var error = Array(repeating: UInt8(0), count: 20)
  error[0] = 0x11
  error[1] = 0xFF
  error[2] = 0xFF
  error[3] = request.featureIndex
  error[4] = request.functionAndSoftwareID
  error[5] = 0x07

  #expect(request.matchesResponse(normal))
  #expect(request.matchesResponse(error))
}

@Test func controlEventsDecodePressedButtonsAndSignedMovement() throws {
  var buttonsPayload = Array(repeating: UInt8(0), count: 16)
  buttonsPayload[0] = 0x00
  buttonsPayload[1] = 0xC3
  let buttons = HIDPPMessage(
    featureIndex: 9,
    functionID: 0,
    softwareID: 0,
    payload: buttonsPayload
  )
  #expect(HIDPPControlEvent.decode(buttons, featureIndex: 9) == .divertedButtons([0x00C3]))

  let movement = HIDPPMessage(
    featureIndex: 9,
    functionID: 1,
    softwareID: 0,
    payload: [0xFF, 0xFB, 0x00, 0x0C]
  )
  #expect(HIDPPControlEvent.decode(movement, featureIndex: 9) == .rawMovement(dx: -5, dy: 12))
}
