import AppKit
import MXMasterCore
import MXMasterLifecycle
import SwiftUI

struct MouseControlsView: View {
  @ObservedObject var controller: MouseController
  let compact: Bool
  @State private var pendingSmartShiftThreshold: Int?
  @State private var debounceTask: Task<Void, Never>?

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      connectionHeader

      switch controller.connectionState {
      case .permissionRequired:
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

      case .blocked(let appName):
        VStack(alignment: .leading, spacing: 8) {
          Text("\(appName) is using the mouse HID++ interface. Quit it to connect.")
            .font(.caption)
            .foregroundStyle(.secondary)
          Button("Refresh") {
            controller.refresh()
          }
          .buttonStyle(.borderedProminent)
        }

      case .error:
        VStack(alignment: .leading, spacing: 8) {
          Text("Something went wrong. Click retry to connect.")
            .font(.caption)
            .foregroundStyle(.secondary)
          Button("Retry") {
            controller.refresh()
          }
          .buttonStyle(.borderedProminent)
        }

      case .reconnecting:
        HStack(spacing: 8) {
          ProgressView().controlSize(.small)
          Text("Reconnecting automatically…")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

      default:
        EmptyView()
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
          Button {
            AppDelegate.shared?.showSettings()
          } label: {
            Label("Settings…", systemImage: "gearshape")
          }
          Button("Quit") { NSApp.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
        }
        .controlSize(.small)
      }
    }
    .padding(compact ? 20 : 0)
    .frame(width: compact ? 340 : nil)
    .task { controller.start() }
  }

  private var connectionHeader: some View {
    HStack(spacing: 12) {
      Image(systemName: connectionIconName)
        .font(.title2)
        .foregroundStyle(connectionColor)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text("MX Master 3").font(.headline)
        Text(controller.connectionState.title)
          .font(.caption)
          .foregroundStyle(connectionColor)
          .lineLimit(2)
      }
      Spacer()
      if controller.isBusy {
        ProgressView().controlSize(.small)
      } else if controller.connectionState.isDisconnected {
        ProgressView().controlSize(.small)
      }
      if let battery = controller.snapshot?.battery {
        Label("\(battery.percentage)%", systemImage: batterySymbol(battery.percentage, charging: battery.statusCode == 2))
          .font(.caption)
          .accessibilityLabel("Battery \(battery.percentage) percent")
      }
    }
  }

  private var connectionIconName: String {
    switch controller.connectionState {
    case .connected: "computermouse.fill"
    case .connecting, .reconnecting: "computermouse"
    case .disconnected: "computermouse"
    case .permissionRequired: "lock.shield"
    case .blocked: "exclamationmark.triangle.fill"
    case .error: "computermouse"
    }
  }

  private var connectionColor: Color {
    switch controller.connectionState {
    case .connected: .green
    case .connecting, .reconnecting: .orange
    case .disconnected: .secondary
    case .permissionRequired: .orange
    case .blocked: .red
    case .error: .secondary
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
        .frame(maxWidth: 150, alignment: .trailing)
        .fixedSize()
      }
    }

    if let smartShift = snapshot.smartShift {
      let displayThreshold = pendingSmartShiftThreshold ?? Int(smartShift.autoDisengage)
      LabeledContent("Wheel mode") {
        Picker("Wheel mode", selection: smartShiftModeBinding(smartShift)) {
          ForEach(SmartShiftMode.allCases, id: \.rawValue) { mode in
            Text(mode.title).tag(mode)
          }
        }
        .labelsHidden()
        .frame(maxWidth: 150, alignment: .trailing)
        .fixedSize()
      }

      Stepper(
        "SmartShift threshold: \(displayThreshold)",
        value: Binding(
          get: { displayThreshold },
          set: { newValue in
            pendingSmartShiftThreshold = newValue
            debounceTask?.cancel()
            debounceTask = Task { @MainActor in
              try? await Task.sleep(for: .milliseconds(300))
              guard !Task.isCancelled else { return }
              let mode =
                SmartShiftMode(
                  rawValue: controller.snapshot?.smartShift?.wheelModeCode ?? smartShift.wheelModeCode
                ) ?? .freeSpin
              controller.setSmartShift(mode: mode, threshold: UInt8(newValue))
              pendingSmartShiftThreshold = nil
            }
          }
        ),
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

  private func wheelInversionBinding(_ wheel: WheelSnapshot) -> Binding<Bool> {
    Binding(
      get: { controller.snapshot?.wheel?.inverted ?? wheel.inverted },
      set: { value in controller.setWheelInverted(value) }
    )
  }

  private func batterySymbol(_ percentage: UInt8, charging: Bool = false) -> String {
    let base: String
    switch percentage {
    case 76...: base = "battery.100percent"
    case 51...: base = "battery.75percent"
    case 26...: base = "battery.50percent"
    case 11...: base = "battery.25percent"
    default: base = "battery.0percent"
    }
    return charging ? base + ".bolt" : base
  }
}
