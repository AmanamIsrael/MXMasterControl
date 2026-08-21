import Testing

import MXMasterHID
import MXMasterLifecycle

@Test func classifyTreatsTransportErrorsAsTransient() {
  let transportErrors: [HIDPPChannelError] = [
    .deviceNotFound,
    .managerOpenFailed(code: 1),
    .deviceOpenFailed(code: 2),
    .reportWriteFailed(code: 3),
    .responseDeliveryFailed(code: 4),
    .responseTimedOut,
    .channelClosed,
  ]
  for error in transportErrors {
    #expect(
      ConnectionClassifier.kind(of: error) == .transient,
      "expected \(error) to be transient"
    )
  }
}

@Test func classifyTreatsUnretryableProtocolErrorsAsFatal() {
  let protocolErrors: [HIDPPChannelError] = [
    .requestAlreadyPending,
    .malformedResponse,
    .deviceError(code: 0x07),
  ]
  for error in protocolErrors {
    #expect(
      ConnectionClassifier.kind(of: error) == .fatal,
      "expected \(error) to be fatal"
    )
  }
}

@Test func classifyMapsDeniedPermissionToPermissionRequired() {
  #expect(ConnectionClassifier.kind(of: HIDPPChannelError.inputMonitoringDenied) == .permissionRequired)
}

@Test func classifyTreatsUnknownErrorsAsFatal() {
  #expect(
    ConnectionClassifier.kind(of: MXMasterServiceError.verificationFailed(setting: "DPI")) == .fatal
  )

  struct UnexpectedError: Error {}
  #expect(ConnectionClassifier.kind(of: UnexpectedError()) == .fatal)
}

@Test func connectionStateTitlesAreUserFacingStrings() {
  #expect(ConnectionState.connecting.title == "Connecting…")
  #expect(ConnectionState.connected.title == "Connected")
  #expect(ConnectionState.disconnected.title == "Mouse not found")
  #expect(ConnectionState.reconnecting.title == "Reconnecting…")
  #expect(ConnectionState.permissionRequired.title == "Input Monitoring required")
  #expect(ConnectionState.blocked("Logi Options+").title == "Quit Logi Options+ to connect")
  #expect(ConnectionState.error.title == "Something went wrong")
}

@Test func isDisconnectedCoversOnlyDisconnectedStates() {
  #expect(!ConnectionState.connecting.isDisconnected)
  #expect(!ConnectionState.connected.isDisconnected)
  #expect(ConnectionState.disconnected.isDisconnected)
  #expect(ConnectionState.reconnecting.isDisconnected)
  #expect(!ConnectionState.permissionRequired.isDisconnected)
  #expect(!ConnectionState.blocked("App").isDisconnected)
  #expect(!ConnectionState.error.isDisconnected)
}

@Test func scheduleDoublesUpToThirtySecondCap() {
  var schedule = ReconnectSchedule()

  #expect(schedule.delay == .seconds(1))

  let expectedProgression: [Duration] = [
    .seconds(2), .seconds(4), .seconds(8), .seconds(16), .seconds(30), .seconds(30),
  ]
  for expected in expectedProgression {
    schedule.advance()
    #expect(schedule.delay == expected)
  }
}

@Test func scheduleResetRestoresBaseDelay() {
  var schedule = ReconnectSchedule()
  schedule.advance()
  schedule.advance()
  #expect(schedule.delay == .seconds(4))

  schedule.reset()
  #expect(schedule.delay == ReconnectSchedule.baseDelay)
}
