import Foundation
import IOKit.hid
import MXMasterCore

public enum HIDPPChannelError: LocalizedError, Equatable {
  case deviceNotFound
  case inputMonitoringDenied
  case managerOpenFailed(code: Int32)
  case deviceOpenFailed(code: Int32)
  case requestAlreadyPending
  case reportWriteFailed(code: Int32)
  case responseTimedOut
  case malformedResponse
  case deviceError(code: UInt8)
  case channelClosed

  public var errorDescription: String? {
    switch self {
    case .deviceNotFound: "The direct-Bluetooth MX Master 3 HID++ interface was not found."
    case .inputMonitoringDenied:
      "Input Monitoring is required to communicate with the MX Master 3."
    case .managerOpenFailed(let code): "IOHIDManager open failed (IOReturn \(code))."
    case .deviceOpenFailed(let code): "MX Master 3 HID open failed (IOReturn \(code))."
    case .requestAlreadyPending: "Another HID++ request is already pending."
    case .reportWriteFailed(let code): "HID++ report write failed (IOReturn \(code))."
    case .responseTimedOut: "The MX Master 3 did not answer the HID++ request in time."
    case .malformedResponse: "The MX Master 3 returned a malformed HID++ response."
    case .deviceError(let code):
      String(format: "The MX Master 3 returned HID++ error 0x%02x.", code)
    case .channelClosed: "The MX Master 3 HID++ channel is closed."
    }
  }
}

/// Owns the direct-Bluetooth IOHID channel and serializes HID++ requests. This first version is
/// intentionally synchronous for the diagnostic CLI; the app-facing session will isolate it on
/// its own actor rather than allowing calls on the main actor.
public final class HIDPPDeviceChannel: @unchecked Sendable {
  private final class PendingResponse {
    let request: HIDPPMessage
    var bytes: [UInt8]?
    var callbackError: Int32?

    init(request: HIDPPMessage) {
      self.request = request
    }
  }

  private let manager: IOHIDManager
  private let device: IOHIDDevice
  private let inputBuffer: UnsafeMutablePointer<UInt8>
  private let callbackQueue = DispatchQueue(label: "com.amanamisrael.MXMasterControl.hid-callback")
  private let sendLock = NSLock()
  private let responseCondition = NSCondition()
  private let eventHandlerLock = NSLock()
  private let cancellationSemaphore = DispatchSemaphore(value: 0)
  private var pendingResponse: PendingResponse?
  private var eventHandler: (@Sendable (HIDPPMessage) -> Void)?
  private var isClosed = false

  public init(identifier: USBIdentifier = HIDDeviceDescriptor.targetIdentifier) throws {
    manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    inputBuffer = .allocate(capacity: 64)
    inputBuffer.initialize(repeating: 0, count: 64)

    let matching: [String: Any] = [
      kIOHIDVendorIDKey as String: identifier.vendorID,
      kIOHIDProductIDKey as String: identifier.productID,
    ]
    IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

    let managerResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    guard managerResult == kIOReturnSuccess else {
      inputBuffer.deinitialize(count: 64)
      inputBuffer.deallocate()
      if managerResult == kIOReturnNotPermitted {
        throw HIDPPChannelError.inputMonitoringDenied
      }
      throw HIDPPChannelError.managerOpenFailed(code: managerResult)
    }

    guard
      let devices = IOHIDManagerCopyDevices(manager),
      let selected = (devices as NSSet)
        .map({ $0 as! IOHIDDevice })
        .first(where: Self.hasLongHIDPPUsage)
    else {
      IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
      inputBuffer.deinitialize(count: 64)
      inputBuffer.deallocate()
      throw HIDPPChannelError.deviceNotFound
    }
    device = selected

    let deviceResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
    guard deviceResult == kIOReturnSuccess else {
      IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
      inputBuffer.deinitialize(count: 64)
      inputBuffer.deallocate()
      throw HIDPPChannelError.deviceOpenFailed(code: deviceResult)
    }

    IOHIDDeviceSetDispatchQueue(device, callbackQueue)
    IOHIDDeviceRegisterInputReportCallback(
      device,
      inputBuffer,
      64,
      { context, result, _, _, reportID, report, reportLength in
        guard let context else { return }
        let channel = Unmanaged<HIDPPDeviceChannel>.fromOpaque(context).takeUnretainedValue()
        channel.receive(
          result: result,
          reportID: UInt8(truncatingIfNeeded: reportID),
          report: report,
          reportLength: reportLength
        )
      },
      Unmanaged.passUnretained(self).toOpaque()
    )
    IOHIDDeviceSetCancelHandler(device) { [cancellationSemaphore] in
      cancellationSemaphore.signal()
    }
    IOHIDDeviceActivate(device)
  }

  deinit {
    close()
    inputBuffer.deinitialize(count: 64)
    inputBuffer.deallocate()
  }

  public func send(_ request: HIDPPMessage, timeout: TimeInterval = 1.5) throws -> HIDPPMessage {
    sendLock.lock()
    defer { sendLock.unlock() }

    responseCondition.lock()
    guard !isClosed else {
      responseCondition.unlock()
      throw HIDPPChannelError.channelClosed
    }
    guard pendingResponse == nil else {
      responseCondition.unlock()
      throw HIDPPChannelError.requestAlreadyPending
    }
    let pending = PendingResponse(request: request)
    pendingResponse = pending
    responseCondition.unlock()

    let bytes = request.encodedLongReport
    let writeResult = bytes.withUnsafeBufferPointer { buffer in
      IOHIDDeviceSetReport(
        device,
        kIOHIDReportTypeOutput,
        CFIndex(HIDPPMessage.longReportID),
        buffer.baseAddress!,
        buffer.count
      )
    }
    guard writeResult == kIOReturnSuccess else {
      clearPending(pending)
      throw HIDPPChannelError.reportWriteFailed(code: writeResult)
    }

    responseCondition.lock()
    let deadline = Date(timeIntervalSinceNow: timeout)
    while pending.bytes == nil && pending.callbackError == nil && !isClosed {
      if !responseCondition.wait(until: deadline) { break }
    }
    let responseBytes = pending.bytes
    let callbackError = pending.callbackError
    let closed = isClosed
    if pendingResponse === pending { pendingResponse = nil }
    responseCondition.unlock()

    if closed { throw HIDPPChannelError.channelClosed }
    if let callbackError { throw HIDPPChannelError.reportWriteFailed(code: callbackError) }
    guard let responseBytes else { throw HIDPPChannelError.responseTimedOut }

    if responseBytes[2] == 0xFF {
      guard responseBytes.count > 5 else { throw HIDPPChannelError.malformedResponse }
      throw HIDPPChannelError.deviceError(code: responseBytes[5])
    }
    guard let response = HIDPPMessage.decodeLongReport(responseBytes) else {
      throw HIDPPChannelError.malformedResponse
    }
    return response
  }

  public func setEventHandler(_ handler: (@Sendable (HIDPPMessage) -> Void)?) {
    eventHandlerLock.lock()
    eventHandler = handler
    eventHandlerLock.unlock()
  }

  public func close() {
    responseCondition.lock()
    guard !isClosed else {
      responseCondition.unlock()
      return
    }
    isClosed = true
    responseCondition.broadcast()
    responseCondition.unlock()

    IOHIDDeviceCancel(device)
    _ = cancellationSemaphore.wait(timeout: .now() + 1)
    IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
    IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
  }

  private func receive(
    result: IOReturn,
    reportID: UInt8,
    report: UnsafeMutablePointer<UInt8>,
    reportLength: CFIndex
  ) {
    responseCondition.lock()
    guard result == kIOReturnSuccess else {
      if let pending = pendingResponse {
        pending.callbackError = result
        responseCondition.signal()
      }
      responseCondition.unlock()
      return
    }
    guard reportID == HIDPPMessage.longReportID else {
      responseCondition.unlock()
      return
    }

    var bytes = Array(UnsafeBufferPointer(start: report, count: reportLength))
    if bytes.first != HIDPPMessage.longReportID {
      bytes.insert(HIDPPMessage.longReportID, at: 0)
    }
    if let pending = pendingResponse, pending.request.matchesResponse(bytes) {
      pending.bytes = bytes
      responseCondition.signal()
      responseCondition.unlock()
      return
    }
    let event = HIDPPMessage.decodeLongReport(bytes)
    responseCondition.unlock()

    guard let event, event.isUnsolicitedEvent else { return }
    eventHandlerLock.lock()
    let handler = eventHandler
    eventHandlerLock.unlock()
    handler?(event)
  }

  private func clearPending(_ pending: PendingResponse) {
    responseCondition.lock()
    if pendingResponse === pending { pendingResponse = nil }
    responseCondition.unlock()
  }

  private static func hasLongHIDPPUsage(_ device: IOHIDDevice) -> Bool {
    guard
      let pairs = IOHIDDeviceGetProperty(device, kIOHIDDeviceUsagePairsKey as CFString)
        as? [[String: Any]]
    else { return false }
    return pairs.contains { pair in
      (pair[kIOHIDDeviceUsagePageKey] as? NSNumber)?.intValue == 0xFF43
        && (pair[kIOHIDDeviceUsageKey] as? NSNumber)?.intValue == 0x0202
    }
  }
}
