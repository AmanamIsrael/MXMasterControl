import Darwin
import Foundation
import MXMasterCore
import MXMasterHID

private enum Command: String {
  case diagnose = "--diagnose"
  case probeFeatures = "--probe-features"
  case readState = "--read-state"
  case readControlReporting = "--read-control-reporting"
  case restoreNativeControlReporting = "--restore-native-control-reporting"
  case captureEvents = "--capture-events"
  case testDPIRoundTrip = "--test-dpi-round-trip"
  case testSettingsRoundTrip = "--test-settings-round-trip"
  case testControlCaptureRoundTrip = "--test-control-capture-round-trip"
  case help = "--help"
}

private struct CapturedControlEvent: Codable {
  let kind: String
  let controls: [UInt16]?
  let dx: Int16?
  let dy: Int16?

  init(_ event: HIDPPControlEvent) {
    switch event {
    case .divertedButtons(let controls):
      kind = "buttons"
      self.controls = controls
      dx = nil
      dy = nil
    case .rawMovement(let dx, let dy):
      kind = "movement"
      controls = nil
      self.dx = dx
      self.dy = dy
    }
  }
}

private final class ControlEventRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var eventCount = 0

  func record(_ event: HIDPPControlEvent) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let data = try? encoder.encode(CapturedControlEvent(event)) else { return }
    lock.lock()
    eventCount += 1
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
    lock.unlock()
  }

  var count: Int {
    lock.lock()
    defer { lock.unlock() }
    return eventCount
  }
}

private func printHelp() {
  print(
    """
    Usage: mxmasterctl [--diagnose | --probe-features | --read-state | --read-control-reporting | --restore-native-control-reporting | --capture-events | --test-dpi-round-trip | --test-settings-round-trip | --test-control-capture-round-trip]

      --diagnose  Print a redacted, read-only JSON inventory for the connected MX Master 3.
      --probe-features
                  Query and print the HID++ feature table without changing settings.
      --read-state
                  Read supported mouse settings and controls without changing them.
      --read-control-reporting
                  Read volatile reporting state for supported secondary controls.
      --restore-native-control-reporting
                  Clear stale non-persistent diversion while preserving persistent remaps.
      --capture-events
                  Capture secondary-button and gesture packets for 15 seconds, then restore.
      --test-dpi-round-trip
                  Set the next supported DPI, verify it, restore the original, and verify again.
      --test-settings-round-trip
                  Verify and restore SmartShift threshold and wheel inversion writes.
      --test-control-capture-round-trip
                  Temporarily divert the four supported secondary controls, then restore them.
      --help      Show this help.

    Diagnostic commands are read-only. Round-trip commands make temporary changes and restore them.
    """)
}

private let argument =
  CommandLine.arguments.dropFirst().first.flatMap(Command.init(rawValue:)) ?? .diagnose

switch argument {
case .help:
  printHelp()

case .diagnose:
  do {
    let enumerator = IOHIDDeviceEnumerator()
    let devices = try enumerator.enumerate(
      identifier: HIDDeviceDescriptor.targetIdentifier)
    let report = HIDDiagnosticReport(
      listenAccess: enumerator.listenAccess,
      matchingDevices: devices
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    FileHandle.standardOutput.write(try encoder.encode(report))
    FileHandle.standardOutput.write(Data("\n".utf8))
    if !report.foundTarget { exit(2) }
  } catch {
    fputs("mxmasterctl: \(error.localizedDescription)\n", stderr)
    exit(1)
  }

case .probeFeatures:
  do {
    let result = try HIDPPReadOnlyProbe().run()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    FileHandle.standardOutput.write(try encoder.encode(result))
    FileHandle.standardOutput.write(Data("\n".utf8))
  } catch {
    fputs("mxmasterctl: \(error.localizedDescription)\n", stderr)
    exit(1)
  }

case .readState:
  do {
    let snapshot = try HIDPPReadOnlyProbe().readState()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    FileHandle.standardOutput.write(try encoder.encode(snapshot))
    FileHandle.standardOutput.write(Data("\n".utf8))
  } catch {
    fputs("mxmasterctl: \(error.localizedDescription)\n", stderr)
    exit(1)
  }

case .readControlReporting:
  do {
    let states = try HIDPPControlReportingProbe().run()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    FileHandle.standardOutput.write(try encoder.encode(states))
    FileHandle.standardOutput.write(Data("\n".utf8))
  } catch {
    fputs("mxmasterctl: \(error.localizedDescription)\n", stderr)
    exit(1)
  }

case .restoreNativeControlReporting:
  do {
    let result = try HIDPPControlReportingReconciler().run()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    FileHandle.standardOutput.write(try encoder.encode(result))
    FileHandle.standardOutput.write(Data("\n".utf8))
  } catch {
    fputs("mxmasterctl: \(error.localizedDescription)\n", stderr)
    exit(1)
  }

case .captureEvents:
  do {
    let requests = [
      ControlCaptureRequest(controlID: MouseControl.back.rawValue, rawMovement: false),
      ControlCaptureRequest(controlID: MouseControl.forward.rawValue, rawMovement: false),
      ControlCaptureRequest(controlID: MouseControl.gesture.rawValue, rawMovement: true),
      ControlCaptureRequest(controlID: MouseControl.smartShift.rawValue, rawMovement: false),
    ]
    let channel = try HIDPPDeviceChannel()
    defer { channel.close() }
    let protocolInfo = try HIDPPReadOnlyProbe().probeFeatures(channel: channel)
    _ = try HIDPPControlReportingReconciler().reconcile(
      controls: MouseControl.allCases,
      channel: channel,
      protocolInfo: protocolInfo
    )
    let recorder = ControlEventRecorder()
    let session = try HIDPPControlCaptureSession(
      channel: channel,
      protocolInfo: protocolInfo,
      requests: requests,
      onEvent: recorder.record
    )
    defer { try? session.close() }

    fputs(
      "mxmasterctl: capture armed for 15 seconds; press secondary buttons and move while holding Gesture\n",
      stderr
    )
    Thread.sleep(forTimeInterval: 15)
    try session.close()
    fputs("mxmasterctl: restored all controls; captured \(recorder.count) events\n", stderr)
  } catch {
    fputs("mxmasterctl: \(error.localizedDescription)\n", stderr)
    exit(1)
  }

case .testDPIRoundTrip:
  do {
    let result = try HIDPPDPIRoundTrip().run()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    FileHandle.standardOutput.write(try encoder.encode(result))
    FileHandle.standardOutput.write(Data("\n".utf8))
  } catch {
    fputs("mxmasterctl: \(error.localizedDescription)\n", stderr)
    exit(1)
  }

case .testSettingsRoundTrip:
  do {
    let result = try HIDPPSettingsRoundTrip().run()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    FileHandle.standardOutput.write(try encoder.encode(result))
    FileHandle.standardOutput.write(Data("\n".utf8))
  } catch {
    fputs("mxmasterctl: \(error.localizedDescription)\n", stderr)
    exit(1)
  }

case .testControlCaptureRoundTrip:
  do {
    let result = try HIDPPControlCaptureRoundTrip().run()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    FileHandle.standardOutput.write(try encoder.encode(result))
    FileHandle.standardOutput.write(Data("\n".utf8))
  } catch {
    fputs("mxmasterctl: \(error.localizedDescription)\n", stderr)
    exit(1)
  }
}
