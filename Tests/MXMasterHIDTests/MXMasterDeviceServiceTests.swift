import Foundation
import Testing

import MXMasterCore
@testable import MXMasterHID

private final class MockHIDPPChannel: HIDPPChannel, @unchecked Sendable {
  private let lock = NSLock()
  private var sentMessages: [HIDPPMessage] = []
  private var storedEventHandler: (@Sendable (HIDPPMessage) -> Void)?
  private let onSend: @Sendable (HIDPPMessage) throws -> HIDPPMessage
  let onClose: @Sendable () -> Void

  init(
    onSend: @escaping @Sendable (HIDPPMessage) throws -> HIDPPMessage,
    onClose: @escaping @Sendable () -> Void = {}
  ) {
    self.onSend = onSend
    self.onClose = onClose
  }

  var recordedMessages: [HIDPPMessage] {
    lock.lock()
    defer { lock.unlock() }
    return sentMessages
  }

  var eventHandler: (@Sendable (HIDPPMessage) -> Void)? {
    lock.lock()
    defer { lock.unlock() }
    return storedEventHandler
  }

  func send(_ request: HIDPPMessage, timeout: TimeInterval) throws -> HIDPPMessage {
    lock.lock()
    sentMessages.append(request)
    lock.unlock()
    return try onSend(request)
  }

  func setEventHandler(_ handler: (@Sendable (HIDPPMessage) -> Void)?) {
    lock.lock()
    storedEventHandler = handler
    lock.unlock()
  }

  func close() {
    onClose()
  }
}

private final class CallCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var value = 0

  func next() -> Int {
    lock.lock()
    defer { lock.unlock() }
    value += 1
    return value
  }

  var count: Int {
    lock.lock()
    defer { lock.unlock() }
    return value
  }
}

private final class Toggle: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Bool

  init(_ value: Bool) {
    self.value = value
  }

  var enabled: Bool {
    get {
      lock.lock()
      defer { lock.unlock() }
      return value
    }
    set {
      lock.lock()
      value = newValue
      lock.unlock()
    }
  }
}

private final class Holder<T>: @unchecked Sendable {
  private let lock = NSLock()
  private var value: T?

  var current: T? {
    lock.lock()
    defer { lock.unlock() }
    return value
  }

  func set(_ value: T) {
    lock.lock()
    self.value = value
    lock.unlock()
  }
}

private final class CallbackBox: @unchecked Sendable {
  private let lock = NSLock()
  private var callback: (@Sendable () -> Void)?

  func set(_ callback: @escaping @Sendable () -> Void) {
    lock.lock()
    self.callback = callback
    lock.unlock()
  }

  func invoke() {
    lock.lock()
    let callback = self.callback
    lock.unlock()
    callback?()
  }
}

private struct ScriptedReportingState {
  var diverted = false
  var persistentlyDiverted = false
  var rawMovement = false
  var forceRawMovement = false
  var remappedControlID: UInt16?
  var analyticsEvents = false
  var rawWheel = false

  func payload(controlID: UInt16) -> [UInt8] {
    var payload = Array(repeating: UInt8(0), count: 16)
    payload[0] = UInt8(controlID >> 8)
    payload[1] = UInt8(controlID & 0xFF)
    if diverted { payload[2] |= 1 << 0 }
    if persistentlyDiverted { payload[2] |= 1 << 2 }
    if rawMovement { payload[2] |= 1 << 4 }
    if forceRawMovement { payload[2] |= 1 << 6 }
    if let remappedControlID {
      payload[3] = UInt8(remappedControlID >> 8)
      payload[4] = UInt8(remappedControlID & 0xFF)
    }
    if analyticsEvents { payload[5] |= 1 << 0 }
    if rawWheel { payload[5] |= 1 << 2 }
    return payload
  }

  mutating func apply(_ payload: [UInt8]) {
    diverted = payload[2] & (1 << 0) != 0
    persistentlyDiverted = payload[2] & (1 << 2) != 0
    rawMovement = payload[2] & (1 << 4) != 0
    forceRawMovement = payload[2] & (1 << 6) != 0
    let remap = UInt16(payload[3]) << 8 | UInt16(payload[4])
    remappedControlID = remap == 0 ? nil : remap
    analyticsEvents = payload[5] & (1 << 0) != 0
    rawWheel = payload[5] & (1 << 2) != 0
  }
}

/// A scripted stand-in for the MX Master 3 that answers every HID++ request the
/// read-only probe, control-table reader, and capture session send.
private final class ScriptedMouse: @unchecked Sendable {
  static let featureSetIndex: UInt8 = 8

  let features: [HIDPPFeatureDescriptor] = [
    HIDPPFeatureDescriptor(tableIndex: 1, featureID: HIDPPFeatureID.battery, typeFlags: 0, version: 1),
    HIDPPFeatureDescriptor(
      tableIndex: 2, featureID: HIDPPFeatureID.adjustableDPI, typeFlags: 0, version: 1),
    HIDPPFeatureDescriptor(
      tableIndex: 3, featureID: HIDPPFeatureID.smartShift, typeFlags: 0, version: 1),
    HIDPPFeatureDescriptor(tableIndex: 4, featureID: HIDPPFeatureID.wheel, typeFlags: 0, version: 1),
    HIDPPFeatureDescriptor(
      tableIndex: 5, featureID: HIDPPFeatureID.reprogrammableControls, typeFlags: 0, version: 1),
  ]

  let controls: [ControlSnapshot] = [
    ControlSnapshot(
      controlID: MouseControl.back.rawValue, defaultTaskID: 0x004A, flags: 0x0020,
      position: 0, group: 1, groupMask: 0),
    ControlSnapshot(
      controlID: MouseControl.forward.rawValue, defaultTaskID: 0x004B, flags: 0x0020,
      position: 1, group: 1, groupMask: 0),
    ControlSnapshot(
      controlID: MouseControl.gesture.rawValue, defaultTaskID: 0x004C, flags: 0x0020,
      position: 2, group: 1, groupMask: 0),
    ControlSnapshot(
      controlID: MouseControl.smartShift.rawValue, defaultTaskID: 0x004D, flags: 0x0020,
      position: 3, group: 1, groupMask: 0),
  ]

  var batteryPercentage: UInt8 = 87
  var batteryStatus: UInt8 = 0
  var dpiCurrent: UInt16 = 1200
  var dpiSupported: [UInt16] = [800, 1000, 1200, 1600]
  var smartShiftMode: UInt8 = 1
  var smartShiftThreshold: UInt8 = 40
  var smartShiftDefaultThreshold: UInt8 = 40
  var wheelModeByte: UInt8 = 0
  var ratchetState: UInt8 = 0
  var reporting: [UInt16: ScriptedReportingState] = [
    MouseControl.back.rawValue: ScriptedReportingState(),
    MouseControl.forward.rawValue: ScriptedReportingState(),
    MouseControl.gesture.rawValue: ScriptedReportingState(),
    MouseControl.smartShift.rawValue: ScriptedReportingState(),
  ]

  private var featureByIndex: [UInt8: UInt16] {
    Dictionary(uniqueKeysWithValues: features.map { ($0.tableIndex, $0.featureID) })
  }

  func responder(_ message: HIDPPMessage) throws -> HIDPPMessage {
    if message.featureIndex == 0 {
      switch message.functionID {
      case 0:
        return HIDPPMessage(featureIndex: 0, functionID: 0, payload: [Self.featureSetIndex, 0, 0])
      case 1:
        return HIDPPMessage(featureIndex: 0, functionID: 1, payload: [5, 0, 0])
      default:
        throw HIDPPChannelError.channelClosed
      }
    }
    if message.featureIndex == Self.featureSetIndex {
      switch message.functionID {
      case 0:
        return HIDPPMessage(
          featureIndex: Self.featureSetIndex, functionID: 0, payload: [UInt8(features.count), 0, 0])
      case 1:
        guard let tableIndex = Int(exactly: message.payload[0]), tableIndex > 0,
          tableIndex <= features.count
        else { throw HIDPPChannelError.malformedResponse }
        let descriptor = features[tableIndex - 1]
        return HIDPPMessage(
          featureIndex: Self.featureSetIndex,
          functionID: 1,
          payload: [
            UInt8(descriptor.featureID >> 8), UInt8(descriptor.featureID & 0xFF),
            descriptor.typeFlags, descriptor.version,
          ])
      default:
        throw HIDPPChannelError.channelClosed
      }
    }

    guard let featureID = featureByIndex[message.featureIndex] else {
      throw HIDPPChannelError.channelClosed
    }
    switch featureID {
    case HIDPPFeatureID.battery:
      guard message.functionID == 0 else { throw HIDPPChannelError.channelClosed }
      return HIDPPMessage(
        featureIndex: message.featureIndex,
        functionID: 0,
        payload: [batteryPercentage, batteryPercentage, batteryStatus])

    case HIDPPFeatureID.adjustableDPI:
      switch message.functionID {
      case 0:
        return HIDPPMessage(featureIndex: message.featureIndex, functionID: 0, payload: [1, 0, 0])
      case 1:
        var payload: [UInt8] = [0]
        for value in dpiSupported {
          payload.append(UInt8(value >> 8))
          payload.append(UInt8(value & 0xFF))
        }
        return HIDPPMessage(featureIndex: message.featureIndex, functionID: 1, payload: payload)
      case 2:
        return HIDPPMessage(
          featureIndex: message.featureIndex,
          functionID: 2,
          payload: [0, UInt8(dpiCurrent >> 8), UInt8(dpiCurrent & 0xFF)])
      case 3:
        dpiCurrent = UInt16(message.payload[1]) << 8 | UInt16(message.payload[2])
        return HIDPPMessage(featureIndex: message.featureIndex, functionID: 3)
      default:
        throw HIDPPChannelError.channelClosed
      }

    case HIDPPFeatureID.smartShift:
      switch message.functionID {
      case 0:
        return HIDPPMessage(
          featureIndex: message.featureIndex,
          functionID: 0,
          payload: [smartShiftMode, smartShiftThreshold, smartShiftDefaultThreshold])
      case 1:
        smartShiftMode = message.payload[0]
        smartShiftThreshold = message.payload[1]
        return HIDPPMessage(featureIndex: message.featureIndex, functionID: 1)
      default:
        throw HIDPPChannelError.channelClosed
      }

    case HIDPPFeatureID.wheel:
      switch message.functionID {
      case 0:
        return HIDPPMessage(
          featureIndex: message.featureIndex,
          functionID: 0,
          payload: [8, 0b0000_1100, 12, 0])
      case 1:
        return HIDPPMessage(
          featureIndex: message.featureIndex, functionID: 1, payload: [wheelModeByte, 0, 0])
      case 2:
        wheelModeByte = message.payload[0]
        return HIDPPMessage(featureIndex: message.featureIndex, functionID: 2)
      case 3:
        return HIDPPMessage(
          featureIndex: message.featureIndex, functionID: 3, payload: [ratchetState, 0, 0])
      default:
        throw HIDPPChannelError.channelClosed
      }

    case HIDPPFeatureID.reprogrammableControls:
      switch message.functionID {
      case 0:
        return HIDPPMessage(
          featureIndex: message.featureIndex, functionID: 0, payload: [UInt8(controls.count), 0, 0])
      case 1:
        guard let row = Int(exactly: message.payload[0]), row >= 0, row < controls.count else {
          throw HIDPPChannelError.malformedResponse
        }
        let snapshot = controls[row]
        return HIDPPMessage(
          featureIndex: message.featureIndex,
          functionID: 1,
          payload: [
            UInt8(snapshot.controlID >> 8), UInt8(snapshot.controlID & 0xFF),
            UInt8(snapshot.defaultTaskID >> 8), UInt8(snapshot.defaultTaskID & 0xFF),
            UInt8(snapshot.flags & 0xFF), snapshot.position, snapshot.group, snapshot.groupMask,
            UInt8(snapshot.flags >> 8),
          ])
      case 2:
        let controlID = UInt16(message.payload[0]) << 8 | UInt16(message.payload[1])
        guard let state = reporting[controlID] else { throw HIDPPChannelError.malformedResponse }
        return HIDPPMessage(
          featureIndex: message.featureIndex,
          functionID: 2,
          payload: state.payload(controlID: controlID))
      case 3:
        let controlID = UInt16(message.payload[0]) << 8 | UInt16(message.payload[1])
        guard var state = reporting[controlID] else {
          throw HIDPPChannelError.malformedResponse
        }
        state.apply(Array(message.payload))
        reporting[controlID] = state
        return HIDPPMessage(featureIndex: message.featureIndex, functionID: 3)
      default:
        throw HIDPPChannelError.channelClosed
      }

    default:
      throw HIDPPChannelError.channelClosed
    }
  }
}

@Test func readStateProducesSnapshotFromScriptedChannel() async throws {
  let mouse = ScriptedMouse()
  let service = MXMasterDeviceService(
    channelFactory: { _ in MockHIDPPChannel(onSend: { try mouse.responder($0) }) }
  )

  let state = try await service.readState()

  #expect(state.battery?.percentage == 87)
  #expect(state.dpi?.current == 1200)
  #expect(state.dpi?.supported == [800, 1000, 1200, 1600])
  #expect(state.smartShift?.wheelModeCode == 1)
  #expect(state.smartShift?.autoDisengage == 40)
  #expect(state.wheel?.inverted == false)
  #expect(state.wheel?.supportsInversion == true)
  #expect(state.thumbWheel == nil)
  #expect(state.controls.map(\.controlID) == MouseControl.allCases.map(\.rawValue))
}

@Test func setDPIAcceptedValueWritesAndVerifies() async throws {
  let mouse = ScriptedMouse()
  let mock = MockHIDPPChannel(onSend: { try mouse.responder($0) })
  let service = MXMasterDeviceService(channelFactory: { _ in mock })

  let state = try await service.setDPI(1600, supportedDPIs: [800, 1000, 1200, 1600])

  #expect(state.dpi?.current == 1600)
  #expect(mouse.dpiCurrent == 1600)
  #expect(
    mock.recordedMessages.contains {
      $0.featureIndex == 2 && $0.functionID == 3 && $0.payload[1] == 0x06 && $0.payload[2] == 0x40
    }
  )
}

@Test func setDPIRejectsUnsupportedValueBeforeWriting() async throws {
  let mouse = ScriptedMouse()
  let mock = MockHIDPPChannel(onSend: { try mouse.responder($0) })
  let service = MXMasterDeviceService(channelFactory: { _ in mock })

  await #expect(throws: MXMasterServiceError.unsupportedDPI(700)) {
    try await service.setDPI(700, supportedDPIs: [800, 1000, 1200, 1600])
  }
  #expect(!mock.recordedMessages.contains { $0.featureIndex == 2 && $0.functionID == 3 })
  #expect(mouse.dpiCurrent == 1200)
}

@Test func applySmartShiftWritesAndVerifies() async throws {
  let mouse = ScriptedMouse()
  let service = MXMasterDeviceService(
    channelFactory: { _ in MockHIDPPChannel(onSend: { try mouse.responder($0) }) }
  )

  try await service.applySmartShift(mode: .ratchet, threshold: 60)

  #expect(mouse.smartShiftMode == SmartShiftMode.ratchet.rawValue)
  #expect(mouse.smartShiftThreshold == 60)
}

@Test func channelFailureResetsConnectionAndNextCallReconnects() async throws {
  let mouse = ScriptedMouse()
  let counter = CallCounter()
  let failBatteryReads = Toggle(true)
  let closeCount = CallCounter()
  let service = MXMasterDeviceService(
    channelFactory: { _ in
      let call = counter.next()
      return MockHIDPPChannel(
        onSend: { message in
          if call == 1, failBatteryReads.enabled, message.featureIndex == 1 {
            throw HIDPPChannelError.responseTimedOut
          }
          return try mouse.responder(message)
        },
        onClose: { closeCount.next() }
      )
    }
  )

  await #expect(throws: HIDPPChannelError.responseTimedOut) {
    try await service.readState()
  }
  failBatteryReads.enabled = false

  let state = try await service.readState()
  #expect(state.battery?.percentage == 87)
  #expect(counter.count == 2)
  #expect(closeCount.count == 1)
}

@Test func waitForDeviceSucceedsAfterTransientFactoryFailure() async {
  let mouse = ScriptedMouse()
  let counter = CallCounter()
  let service = MXMasterDeviceService(
    channelFactory: { _ in
      if counter.next() == 1 { throw HIDPPChannelError.deviceNotFound }
      return MockHIDPPChannel(onSend: { try mouse.responder($0) })
    }
  )

  let ready = await service.waitForDevice(timeout: 0.9)

  #expect(ready)
  #expect(counter.count == 2)
}

@Test func invalidateClosesActiveChannelAndNextReadReconnects() async throws {
  let mouse = ScriptedMouse()
  let counter = CallCounter()
  let closeCount = CallCounter()
  let service = MXMasterDeviceService(
    channelFactory: { _ in
      _ = counter.next()
      return MockHIDPPChannel(
        onSend: { try mouse.responder($0) },
        onClose: { closeCount.next() }
      )
    }
  )

  _ = try await service.readState()
  await service.invalidate()

  #expect(closeCount.count == 1)
  _ = try await service.readState()
  #expect(counter.count == 2)
}

@Test func disconnectCallbackClearsConnectionAndReconnectRebuilds() async throws {
  let mouse = ScriptedMouse()
  let counter = CallCounter()
  let serviceOnDisconnect = CallCounter()
  let internalDisconnect = CallbackBox()
  let service = MXMasterDeviceService(
    onDisconnect: { serviceOnDisconnect.next() },
    channelFactory: { onDisconnect in
      internalDisconnect.set(onDisconnect)
      _ = counter.next()
      return MockHIDPPChannel(onSend: { try mouse.responder($0) })
    }
  )

  _ = try await service.readState()
  internalDisconnect.invoke()

  let state = try await service.readState()
  #expect(state.battery?.percentage == 87)
  #expect(counter.count == 2)
  #expect(serviceOnDisconnect.count == 1)
}

@Test func configureControlCaptureArmsControlsAndCachesRepeatRequests() async throws {
  let mouse = ScriptedMouse()
  let counter = CallCounter()
  let mockHolder = Holder<MockHIDPPChannel>()
  let service = MXMasterDeviceService(
    channelFactory: { _ in
      _ = counter.next()
      let channel = MockHIDPPChannel(onSend: { try mouse.responder($0) })
      mockHolder.set(channel)
      return channel
    }
  )

  let requests = [
    ControlCaptureRequest(controlID: MouseControl.back.rawValue, rawMovement: false),
    ControlCaptureRequest(controlID: MouseControl.forward.rawValue, rawMovement: false),
  ]
  try await service.configureControlCapture(requests: requests) { _ in }

  #expect(mouse.reporting[MouseControl.back.rawValue]?.diverted == true)
  #expect(mouse.reporting[MouseControl.forward.rawValue]?.diverted == true)
  #expect(mouse.reporting[MouseControl.gesture.rawValue]?.diverted == false)
  #expect(mockHolder.current?.eventHandler != nil)

  let messageCountAfterArming = mockHolder.current?.recordedMessages.count ?? 0
  try await service.configureControlCapture(requests: requests) { _ in }

  #expect(mockHolder.current?.recordedMessages.count == messageCountAfterArming)
  #expect(counter.count == 1)

  await service.invalidate()
  #expect(mouse.reporting[MouseControl.back.rawValue]?.diverted == false)
  #expect(mouse.reporting[MouseControl.forward.rawValue]?.diverted == false)
}