import Foundation
import IOKit.hid
import MXMasterCore
import os

/// Watches IOHID for the target device appearing (Bluetooth connect, pairing,
/// or wake) so the app can reconnect the moment the mouse returns instead of
/// waiting out a backoff tick. Purely observational: it never opens, seizes, or
/// configures a device, so it coexists with channel managers and preserves
/// read-only diagnostics.
public final class HIDPPDeviceMonitor: @unchecked Sendable {
  private static let logger = Logger(
    subsystem: "com.amanamisrael.MXMasterControl",
    category: "hid"
  )

  private let identifier: USBIdentifier
  private let callbackQueue = DispatchQueue(
    label: "com.amanamisrael.MXMasterControl.device-monitor")
  private let stateLock = NSLock()
  private var manager: IOHIDManager?
  private var onArrival: (@Sendable () -> Void)?

  public init(identifier: USBIdentifier = HIDDeviceDescriptor.targetIdentifier) {
    self.identifier = identifier
  }

  deinit {
    stop()
  }

  /// Starts observing. The handler may be invoked several times per physical
  /// arrival (the mouse exposes multiple matching HID interfaces); consumers
  /// should debounce. Safe to call again to replace the handler.
  public func start(onArrival: @escaping @Sendable () -> Void) {
    stateLock.lock()
    if manager != nil {
      self.onArrival = onArrival
      stateLock.unlock()
      return
    }
    self.onArrival = onArrival
    stateLock.unlock()

    let newManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    // VID/PID only: usage-pair filtering happens downstream because device
    // properties are not guaranteed to be populated at match-callback time.
    let matching: [String: Any] = [
      kIOHIDVendorIDKey as String: identifier.vendorID,
      kIOHIDProductIDKey as String: identifier.productID,
    ]
    IOHIDManagerSetDeviceMatching(newManager, matching as CFDictionary)
    IOHIDManagerSetDispatchQueue(newManager, callbackQueue)

    let context = Unmanaged.passUnretained(self).toOpaque()
    IOHIDManagerRegisterDeviceMatchingCallback(
      newManager,
      { context, _, _, _ in
        guard let context else { return }
        let monitor = Unmanaged<HIDPPDeviceMonitor>.fromOpaque(context).takeUnretainedValue()
        monitor.deviceMatched()
      },
      context
    )

    let result = IOHIDManagerOpen(newManager, IOOptionBits(kIOHIDOptionsTypeNone))
    guard result == kIOReturnSuccess else {
      Self.logger.error(
        "Device monitor failed to open IOHIDManager (IOReturn \(result)); arrival events unavailable"
      )
      stateLock.lock()
      self.onArrival = nil
      stateLock.unlock()
      return
    }

    stateLock.lock()
    manager = newManager
    stateLock.unlock()
  }

  public func stop() {
    stateLock.lock()
    let existing = manager
    manager = nil
    onArrival = nil
    stateLock.unlock()
    guard let existing else { return }
    IOHIDManagerClose(existing, IOOptionBits(kIOHIDOptionsTypeNone))
  }

  private func deviceMatched() {
    stateLock.lock()
    let handler = onArrival
    stateLock.unlock()
    guard let handler else { return }
    Self.logger.debug("Target device matched by IOHID")
    handler()
  }
}
