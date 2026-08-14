import AppKit
import SwiftUI

@main
struct MXMasterControlApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @StateObject private var controller = MouseController.shared

  var body: some Scene {
    MenuBarExtra {
      MouseControlsView(controller: controller, compact: true)
    } label: {
      Image(systemName: controller.snapshot == nil ? "computermouse" : "computermouse.fill")
        .accessibilityLabel("MX Master Control")
    }
    .menuBarExtraStyle(.window)

    Settings {
      SettingsView(controller: controller)
    }

  }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
  private var developmentSettingsWindow: NSWindow?

  func applicationDidFinishLaunching(_ notification: Notification) {
    guard CommandLine.arguments.contains("--show-settings") else { return }
    NSApp.setActivationPolicy(.regular)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 620, height: 560),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = "MX Master Control"
    window.minSize = NSSize(width: 560, height: 500)
    window.setFrameAutosaveName("MXMasterControlDevelopmentSettings")
    window.contentViewController = NSHostingController(
      rootView: SettingsView(controller: MouseController.shared)
    )
    window.center()
    developmentSettingsWindow = window
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
  }
}
