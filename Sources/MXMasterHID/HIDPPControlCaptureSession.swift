import Foundation
import MXMasterCore

public enum ControlCaptureError: LocalizedError, Equatable {
  case featureUnavailable
  case controlUnavailable(UInt16)
  case controlNotDivertable(UInt16)
  case armingNotConfirmed(UInt16)
  case restorationNotConfirmed(UInt16)
  case rollbackFailed

  public var errorDescription: String? {
    switch self {
    case .featureUnavailable: "The mouse does not expose Reprogrammable Controls (0x1b04)."
    case .controlUnavailable(let control):
      String(format: "Control 0x%04x is not present on this mouse.", control)
    case .controlNotDivertable(let control):
      String(format: "Control 0x%04x cannot be temporarily diverted.", control)
    case .armingNotConfirmed(let control):
      String(format: "Temporary diversion was not confirmed for control 0x%04x.", control)
    case .restorationNotConfirmed(let control):
      String(format: "Original reporting state was not restored for control 0x%04x.", control)
    case .rollbackFailed:
      "Control capture failed and at least one original reporting state could not be restored."
    }
  }
}

/// Captures one or more HID++ controls without persistent firmware changes. It uses a single
/// HID++ channel, records every original reporting state before modifying anything, and restores
/// all armed controls when closed.
public final class HIDPPControlCaptureSession: @unchecked Sendable {
  private enum Lifecycle {
    case open
    case restoring
    case closed
  }

  private let channel: HIDPPDeviceChannel
  private let featureIndex: UInt8
  private let closesChannelOnClose: Bool
  private let lifecycleCondition = NSCondition()
  private var lifecycle = Lifecycle.open
  private var originalStates: [UInt16: ControlReportingState] = [:]
  private var armedControlIDs: [UInt16] = []

  public convenience init(
    controlID: UInt16,
    rawMovement: Bool,
    onEvent: @escaping @Sendable (HIDPPControlEvent) -> Void
  ) throws {
    let channel = try HIDPPDeviceChannel()
    do {
      let protocolInfo = try HIDPPReadOnlyProbe().probeFeatures(channel: channel)
      try self.init(
        channel: channel,
        protocolInfo: protocolInfo,
        requests: [ControlCaptureRequest(controlID: controlID, rawMovement: rawMovement)],
        closesChannelOnClose: true,
        onEvent: onEvent
      )
    } catch {
      channel.close()
      throw error
    }
  }

  public init(
    channel: HIDPPDeviceChannel,
    protocolInfo: HIDPPProbeResult,
    requests: [ControlCaptureRequest],
    closesChannelOnClose: Bool = false,
    onEvent: @escaping @Sendable (HIDPPControlEvent) -> Void
  ) throws {
    guard
      let featureIndex = protocolInfo.features.first(where: { $0.featureID == 0x1B04 })?
        .tableIndex
    else { throw ControlCaptureError.featureUnavailable }

    self.channel = channel
    self.featureIndex = featureIndex
    self.closesChannelOnClose = closesChannelOnClose

    do {
      let controls = try Self.readControls(featureIndex: featureIndex, channel: channel)
      let controlsByID = Dictionary(uniqueKeysWithValues: controls.map { ($0.controlID, $0) })

      for request in requests {
        guard let control = controlsByID[request.controlID] else {
          throw ControlCaptureError.controlUnavailable(request.controlID)
        }
        guard control.flags & (1 << 5) != 0 else {
          throw ControlCaptureError.controlNotDivertable(request.controlID)
        }
      }

      for request in requests {
        let originalState = try Self.readReporting(
          controlID: request.controlID,
          featureIndex: featureIndex,
          channel: channel
        )
        originalStates[request.controlID] = originalState
        armedControlIDs.append(request.controlID)

        _ = try channel.send(
          HIDPPMessage(
            featureIndex: featureIndex,
            functionID: 3,
            payload: originalState.temporaryDiversionPayload(rawMovement: request.rawMovement)
          ))
        let armed = try Self.readReporting(
          controlID: request.controlID,
          featureIndex: featureIndex,
          channel: channel
        )
        guard armed.diverted, !request.rawMovement || armed.rawMovement else {
          throw ControlCaptureError.armingNotConfirmed(request.controlID)
        }
      }

      channel.setEventHandler { message in
        guard let event = HIDPPControlEvent.decode(message, featureIndex: featureIndex) else {
          return
        }
        onEvent(event)
      }
    } catch {
      channel.setEventHandler(nil)
      let rollbackSucceeded = (try? restoreArmedControls()) != nil
      if closesChannelOnClose { channel.close() }
      if !rollbackSucceeded, !armedControlIDs.isEmpty {
        throw ControlCaptureError.rollbackFailed
      }
      throw error
    }
  }

  deinit {
    try? close()
    if closesChannelOnClose { channel.close() }
  }

  public func close() throws {
    lifecycleCondition.lock()
    while lifecycle == .restoring {
      lifecycleCondition.wait()
    }
    guard lifecycle != .closed else {
      lifecycleCondition.unlock()
      return
    }
    lifecycle = .restoring
    lifecycleCondition.unlock()

    channel.setEventHandler(nil)
    do {
      try restoreArmedControls()
      if closesChannelOnClose { channel.close() }
      lifecycleCondition.lock()
      lifecycle = .closed
      lifecycleCondition.broadcast()
      lifecycleCondition.unlock()
    } catch {
      lifecycleCondition.lock()
      if lifecycle != .closed { lifecycle = .open }
      lifecycleCondition.broadcast()
      lifecycleCondition.unlock()
      throw error
    }
  }

  /// Ends bookkeeping without sending restoration reports after the device has physically gone
  /// away. Temporary diversion belongs to the vanished HID++ session and cannot be restored over
  /// its dead channel; a reconnect creates and reconciles a new session.
  public func abandonAfterDeviceRemoval() {
    channel.setEventHandler(nil)
    lifecycleCondition.lock()
    lifecycle = .closed
    lifecycleCondition.broadcast()
    lifecycleCondition.unlock()
  }

  private func restoreArmedControls() throws {
    var firstError: Error?
    for controlID in armedControlIDs.reversed() {
      guard let originalState = originalStates[controlID] else { continue }
      do {
        _ = try channel.send(
          HIDPPMessage(
            featureIndex: featureIndex,
            functionID: 3,
            payload: originalState.restorationPayload
          ))
        let restored = try Self.readReporting(
          controlID: controlID,
          featureIndex: featureIndex,
          channel: channel
        )
        guard restored == originalState else {
          throw ControlCaptureError.restorationNotConfirmed(controlID)
        }
      } catch {
        if firstError == nil { firstError = error }
      }
    }
    if let firstError { throw firstError }
  }

  private static func readControls(
    featureIndex: UInt8,
    channel: HIDPPDeviceChannel
  ) throws -> [ControlSnapshot] {
    let count = try channel.send(HIDPPMessage(featureIndex: featureIndex, functionID: 0)).payload[0]
    guard count > 0 else { return [] }
    return try (UInt8(0)..<count).map { row in
      let response = try channel.send(
        HIDPPMessage(featureIndex: featureIndex, functionID: 1, payload: [row])
      )
      return ControlSnapshot(
        controlID: UInt16(response.payload[0]) << 8 | UInt16(response.payload[1]),
        defaultTaskID: UInt16(response.payload[2]) << 8 | UInt16(response.payload[3]),
        flags: UInt16(response.payload[4]) | UInt16(response.payload[8]) << 8,
        position: response.payload[5],
        group: response.payload[6],
        groupMask: response.payload[7]
      )
    }
  }

  private static func readReporting(
    controlID: UInt16,
    featureIndex: UInt8,
    channel: HIDPPDeviceChannel
  ) throws -> ControlReportingState {
    let response = try channel.send(
      HIDPPMessage(
        featureIndex: featureIndex,
        functionID: 2,
        payload: [UInt8(controlID >> 8), UInt8(controlID & 0xFF), 0]
      ))
    return ControlReportingState(payload: response.payload)
  }
}
