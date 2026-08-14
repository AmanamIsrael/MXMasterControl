import AppKit
import MXMasterCore
import SwiftUI

struct MouseControlsView: View {
  @ObservedObject var controller: MouseController
  let compact: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      connectionHeader

      if controller.connectionState == .permissionRequired {
        VStack(alignment: .leading, spacing: 8) {
          Text(
            "Allow MX Master Control in System Settings → Privacy & Security → Input Monitoring, then return and refresh."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          Button("Request Input Monitoring") {
            controller.requestInputMonitoringAccess()
          }
          .buttonStyle(.borderedProminent)
          Button("Open System Settings") {
            controller.openInputMonitoringSettings()
          }
        }
      }

      if let snapshot = controller.snapshot {
        Divider()
        controls(snapshot)
      }

      if compact {
        Divider()
        HStack {
          Button {
            controller.refresh()
          } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
          }
          .keyboardShortcut("r", modifiers: .command)
          .disabled(controller.isBusy)

          Spacer()
          SettingsLink {
            Label("Settings…", systemImage: "gearshape")
          }
          Button("Quit") { NSApp.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
        }
        .controlSize(.small)
      }
    }
    .padding(20)
    .frame(width: compact ? 340 : nil)
    .task { controller.start() }
  }

  private var connectionHeader: some View {
    HStack(spacing: 12) {
      Image(systemName: controller.snapshot == nil ? "computermouse" : "computermouse.fill")
        .font(.title2)
        .foregroundStyle(controller.snapshot == nil ? .secondary : .primary)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text("MX Master 3").font(.headline)
        Text(controller.connectionState.title)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }
      Spacer()
      if controller.isBusy { ProgressView().controlSize(.small) }
      if let battery = controller.snapshot?.battery {
        Label("\(battery.percentage)%", systemImage: batterySymbol(battery.percentage))
          .font(.caption)
          .accessibilityLabel("Battery \(battery.percentage) percent")
      }
    }
  }

  @ViewBuilder
  private func controls(_ snapshot: MXMasterReadOnlySnapshot) -> some View {
    if let dpi = snapshot.dpi {
      LabeledContent("Pointer speed") {
        Picker("Pointer speed", selection: dpiBinding(dpi)) {
          ForEach(dpi.supported, id: \.self) { value in
            Text("\(value) DPI").tag(value)
          }
        }
        .labelsHidden()
        .frame(width: 130)
      }
    }

    if let smartShift = snapshot.smartShift {
      LabeledContent("Wheel mode") {
        Picker("Wheel mode", selection: smartShiftModeBinding(smartShift)) {
          ForEach(SmartShiftMode.allCases, id: \.rawValue) { mode in
            Text(mode.title).tag(mode)
          }
        }
        .labelsHidden()
        .frame(width: 130)
      }

      Stepper(
        "SmartShift threshold: \(smartShift.autoDisengage)",
        value: smartShiftThresholdBinding(smartShift),
        in: 1...254
      )
    }

    if let wheel = snapshot.wheel, wheel.supportsInversion {
      Toggle("Reverse vertical scrolling", isOn: wheelInversionBinding(wheel))
    }
  }

  private func dpiBinding(_ dpi: DPISnapshot) -> Binding<UInt16> {
    Binding(
      get: { controller.snapshot?.dpi?.current ?? dpi.current },
      set: { value in controller.setDPI(value) }
    )
  }

  private func smartShiftModeBinding(_ smartShift: SmartShiftSnapshot) -> Binding<SmartShiftMode> {
    Binding(
      get: {
        SmartShiftMode(
          rawValue: controller.snapshot?.smartShift?.wheelModeCode ?? smartShift.wheelModeCode)
          ?? .freeSpin
      },
      set: { mode in
        controller.setSmartShift(
          mode: mode,
          threshold: controller.snapshot?.smartShift?.autoDisengage ?? smartShift.autoDisengage
        )
      }
    )
  }

  private func smartShiftThresholdBinding(_ smartShift: SmartShiftSnapshot) -> Binding<Int> {
    Binding(
      get: { Int(controller.snapshot?.smartShift?.autoDisengage ?? smartShift.autoDisengage) },
      set: { value in
        let mode =
          SmartShiftMode(
            rawValue: controller.snapshot?.smartShift?.wheelModeCode ?? smartShift.wheelModeCode
          ) ?? .freeSpin
        controller.setSmartShift(mode: mode, threshold: UInt8(value))
      }
    )
  }

  private func wheelInversionBinding(_ wheel: WheelSnapshot) -> Binding<Bool> {
    Binding(
      get: { controller.snapshot?.wheel?.inverted ?? wheel.inverted },
      set: { value in controller.setWheelInverted(value) }
    )
  }

  private func batterySymbol(_ percentage: UInt8) -> String {
    switch percentage {
    case 76...: "battery.100percent"
    case 51...: "battery.75percent"
    case 26...: "battery.50percent"
    case 11...: "battery.25percent"
    default: "battery.0percent"
    }
  }
}
