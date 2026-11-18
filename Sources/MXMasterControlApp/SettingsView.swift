import MXMasterCore
import SwiftUI

struct SettingsView: View {
  @ObservedObject var controller: MouseController

  var body: some View {
    Form {
      Section("Mouse") {
        MouseControlsView(controller: controller, compact: false)
      }

      Section("Scrolling") {
        Toggle(
          "Trackpad-style scrolling",
          isOn: Binding(
            get: { controller.configuration.trackpadScrolling },
            set: { controller.setTrackpadScrollingEnabled($0) }
          )
        )
        Text(
          "Smooth scrolling with momentum, like a trackpad, for both wheels. Flick the wheel to glide, and turn it back one notch to stop. Hold Shift to scroll sideways with the main wheel."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        Toggle(
          "Zoom with Command-scroll",
          isOn: Binding(
            get: { controller.configuration.pinchZoom },
            set: { controller.setPinchZoomEnabled($0) }
          )
        )
        Text(
          "Hold Command and turn the main wheel to zoom like a pinch on a trackpad. Turn it away from you to zoom in."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
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
        Text(
          "The menu bar icon hides while the mouse is away and returns when it reconnects. Open MX Master Control again to show this window."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      Section("Buttons") {
        ForEach([MouseControl.back, .forward, .smartShift]) { control in
          Picker(control.title, selection: actionBinding(for: control)) {
            ForEach(MouseAction.allCases) { action in
              Text(action.title).tag(action)
            }
          }
        }

        Toggle(
          "Gesture navigation",
          isOn: Binding(
            get: { controller.configuration.gestureNavigationEnabled },
            set: { controller.setGestureNavigationEnabled($0) }
          )
        )

        if controller.configuration.gestureNavigationEnabled {
          Text(
            "Hold the gesture button: move left or right between desktops, up for Mission Control, down for App Exposé, or click to show the desktop."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          DisclosureGroup("Gesture actions") {
            ForEach(GestureDirection.allCases) { direction in
              Picker(direction.title, selection: gestureActionBinding(for: direction)) {
                ForEach(MouseAction.allCases.filter { $0 != .systemDefault }) { action in
                  Text(action.title).tag(action)
                }
              }
            }
          }
        } else {
          Picker("Gesture button", selection: actionBinding(for: .gesture)) {
            ForEach(MouseAction.allCases) { action in
              Text(action.title).tag(action)
            }
          }
        }

        if controller.configuration.requiresAccessibility, !controller.accessibilityGranted {
          Text(
            "Custom actions, trackpad-style scrolling and zooming stay off—and the mouse keeps its native behavior—until Accessibility is allowed."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          HStack {
            Button("Request Accessibility") {
              controller.requestAccessibilityAccess()
            }
            .buttonStyle(.borderedProminent)
            Button("Open System Settings") {
              controller.openAccessibilitySettings()
            }
          }
        }

        if let error = controller.actionError {
          Text(error).font(.caption).foregroundStyle(.red)
        }
      }

      Section("Diagnostics") {
        LabeledContent("Connection", value: controller.connectionState.title)
        LabeledContent("Controls discovered", value: "\(controller.snapshot?.controls.count ?? 0)")
        LabeledContent(
          "Custom controls",
          value: controller.controlCaptureActive ? "Active" : "Native"
        )
        Text(
          "Settings are confirmed by reading them back from the mouse. Saved values are reapplied after wake or reconnection."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .frame(minWidth: 400, minHeight: 400)
  }

  private func actionBinding(for control: MouseControl) -> Binding<MouseAction> {
    Binding(
      get: { controller.configuration.action(for: control) },
      set: { controller.setAction($0, for: control) }
    )
  }

  private func gestureActionBinding(for direction: GestureDirection) -> Binding<MouseAction> {
    Binding(
      get: { controller.configuration.gestureActions.action(for: direction) },
      set: { controller.setGestureAction($0, for: direction) }
    )
  }
}
