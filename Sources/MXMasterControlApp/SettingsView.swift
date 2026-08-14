import MXMasterCore
import SwiftUI

struct SettingsView: View {
  @ObservedObject var controller: MouseController

  var body: some View {
    Form {
      Section("Mouse") {
        MouseControlsView(controller: controller, compact: false)
          .padding(-20)
      }

      Section("General") {
        Toggle(
          "Launch MX Master Control at login",
          isOn: Binding(
            get: { controller.launchAtLogin },
            set: { enabled in controller.setLaunchAtLogin(enabled) }
          )
        )
        if let error = controller.launchAtLoginError {
          Text(error).font(.caption).foregroundStyle(.red)
        }
      }

      Section("Diagnostics") {
        LabeledContent("Connection", value: controller.connectionState.title)
        LabeledContent("Controls discovered", value: "\(controller.snapshot?.controls.count ?? 0)")
        Text(
          "Settings are confirmed by reading them back from the mouse. Saved values are reapplied after wake or reconnection."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .frame(minWidth: 560, minHeight: 500)
  }
}
