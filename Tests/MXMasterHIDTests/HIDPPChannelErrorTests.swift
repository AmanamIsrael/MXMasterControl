import Testing

@testable import MXMasterHID

@Test func channelErrorsRemainActionable() {
  let error = HIDPPChannelError.deviceError(code: 7)
  #expect(error.errorDescription?.contains("0x07") == true)
}
