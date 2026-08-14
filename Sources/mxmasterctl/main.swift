import Darwin
import Foundation
import MXMasterCore
import MXMasterHID

private enum Command: String {
  case diagnose = "--diagnose"
  case probeFeatures = "--probe-features"
  case readState = "--read-state"
  case testDPIRoundTrip = "--test-dpi-round-trip"
  case testSettingsRoundTrip = "--test-settings-round-trip"
  case testControlCaptureRoundTrip = "--test-control-capture-round-trip"
  case help = "--help"
}

private func printHelp() {
  print(
    """
    Usage: mxmasterctl [--diagnose | --probe-features | --read-state | --test-dpi-round-trip | --test-settings-round-trip | --test-control-capture-round-trip]

      --diagnose  Print a redacted, read-only JSON inventory for the connected MX Master 3.
      --probe-features
                  Query and print the HID++ feature table without changing settings.
      --read-state
                  Read supported mouse settings and controls without changing them.
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
