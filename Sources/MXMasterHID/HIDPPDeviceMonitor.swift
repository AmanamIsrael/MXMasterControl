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

  /// Signals when the manager's cancel handler has drained all queued events,
  /// making it safe to drop the manager (and its unretained callback context).
  private final class CancellationSignal: @unchecked Sendable {
    let semaphore = DispatchSemaphore(value: 0)
  }

  private let identifier: USBIdentifier
  private let callbackQueue = DispatchQueue(
    label: "com.amanamisrael.MXMasterControl.device-monitor")
  private let stateLock = NSLock()
  private var manager: IOHIDManager?
  private var cancellation: CancellationSignal?
  private var onArrival: (@Sendable () -> Void)?

  public init(identifier: USBIdentifier = HIDDeviceDescriptor.targetIdentifier) {
    self.identifier = identifier
  }

  deinit {
    stop()
  }

  /// Starts observing. The handler may be invoked several times per physical
  /// arrival (the mouse exposes multiple matching HID interfaces); consumers
  /// should debounce. Safe to call again to replace the handler, and to call
  /// again after a failed start (e.g. once Input Monitoring is granted).
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

    let openResult = IOHIDManagerOpen(newManager, IOOptionBits(kIOHIDOptionsTypeNone))
    guard openResult == kIOReturnSuccess else {
      Self.logger.error(
        "Device monitor failed to open IOHIDManager (IOReturn \(openResult)); arrival events unavailable"
      )
      stateLock.lock()
      self.onArrival = nil
      stateLock.unlock()
      return
    }

    // A queue-scheduled manager stays inert until activated, and registration
    // must happen before activation (see IOHIDManager.h). The cancel handler is
    // also installed up front because it cannot be added after activation; stop()
    // waits on it before releasing the manager that holds an unretained `self`.
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
    IOHIDManagerSetDispatchQueue(newManager, callbackQueue)

    let signal = CancellationSignal()
    IOHIDManagerSetCancelHandler(newManager, { [signal] in signal.semaphore.signal() })
    IOHIDManagerActivate(newManager)

    stateLock.lock()
    manager = newManager
    cancellation = signal
    stateLock.unlock()
  }

  public func stop() {
    stateLock.lock()
    let existing = manager
    manager = nil
    let signal = cancellation
    cancellation = nil
    onArrival = nil
    stateLock.unlock()
    guard let existing else { return }
    IOHIDManagerClose(existing, IOOptionBits(kIOHIDOptionsTypeNone))
    IOHIDManagerCancel(existing)
    if let signal {
      _ = signal.semaphore.wait(timeout: .now() + 2)
    }
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
