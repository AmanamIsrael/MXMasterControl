import Testing

@testable import MXMasterCore

@Test func controlSnapshotDecodesEveryFieldFromPayload() {
  let snapshot = ControlSnapshot(
    payload: [0x00, 0xC3, 0x00, 0x52, 0x84, 0x02, 0x03, 0x04, 0x01]
  )

  #expect(snapshot.controlID == 0x00C3)
  #expect(snapshot.defaultTaskID == 0x0052)
  #expect(snapshot.flags == 0x0184)
  #expect(snapshot.position == 0x02)
  #expect(snapshot.group == 0x03)
  #expect(snapshot.groupMask == 0x04)
}

@Test func probeResultFindsFeatureIndexByID() {
  let info = HIDPPProbeResult(
    protocolNumber: 5,
    targetSoftware: 0,
    features: [
      HIDPPFeatureDescriptor(
        tableIndex: 3,
        featureID: HIDPPFeatureID.adjustableDPI,
        typeFlags: 0,
        version: 1
      )
    ]
  )

  #expect(info.index(of: HIDPPFeatureID.adjustableDPI) == 3)
  #expect(info.index(of: HIDPPFeatureID.smartShift) == nil)
}