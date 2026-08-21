import AppKit
import MXMasterLifecycle
import SwiftUI

@main
struct MXMasterControlApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @StateObject private var controller = MouseController.shared

  var body: some Scene {
    MenuBarExtra {
      MouseControlsView(controller: controller, compact: true)
    } label: {
      menuBarLabel
    }
    .menuBarExtraStyle(.window)
  }

  private var menuBarLabel: some View {
    menuBarImage
      .accessibilityLabel(menuBarAccessibilityLabel)
  }

  @ViewBuilder
  private var menuBarImage: some View {
    switch controller.connectionState {
    case .connected:
      Image(systemName: "computermouse.fill").foregroundStyle(.green)
    case .connecting, .reconnecting:
      Image(systemName: "computermouse").foregroundStyle(.orange)
    case .disconnected:
      Image(systemName: "computermouse").foregroundStyle(.secondary)
    case .permissionRequired:
      Image(systemName: "computermouse").foregroundStyle(.orange)
    case .blocked:
      Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
    case .error:
      Image(systemName: "computermouse").foregroundStyle(.secondary)
    }
  }

  private var menuBarAccessibilityLabel: String {
    switch controller.connectionState {
    case .connected: "MX Master Control — Connected"
    case .connecting, .reconnecting: "MX Master Control — Reconnecting"
    case .disconnected: "MX Master Control — Not found"
    case .permissionRequired: "MX Master Control — Permission required"
    case .blocked: "MX Master Control — Blocked"
    case .error: "MX Master Control — Connection issue"
    }
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  static weak var shared: AppDelegate?
  private var settingsWindow: NSWindow?
  private var terminationPrepared = false

  func applicationDidFinishLaunching(_ notification: Notification) {
    Self.shared = self
    MouseController.shared.start()
    if CommandLine.arguments.contains("--show-settings") {
      DispatchQueue.main.async { self.showSettings() }
    }
  }

  func showSettings() {
    let window = settingsWindow ?? makeSettingsWindow()

    NSApp.setActivationPolicy(.regular)
    presentSettingsWindow(window)

    // Opening from a MenuBarExtra dismisses its panel at the end of the current
    // event. Wait for that dismissal, then reassert both app activation and
    // window ordering so the panel cannot steal focus back.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
      self.presentSettingsWindow(window)
    }
  }

  private func presentSettingsWindow(_ window: NSWindow) {
    NSRunningApplication.current.activate(options: [.activateAllWindows])
    NSApp.activate(ignoringOtherApps: true)
    if window.isMiniaturized {
      window.deminiaturize(nil)
    }
    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()
  }

  private func makeSettingsWindow() -> NSWindow {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 600, height: 600),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = "MX Master Control"
    window.minSize = NSSize(width: 400, height: 400)
    window.isReleasedWhenClosed = false
    window.level = .floating
    window.hidesOnDeactivate = false
    window.collectionBehavior.insert(.moveToActiveSpace)
    window.setFrameAutosaveName("MXMasterControlSettings")
    window.contentViewController = NSHostingController(
      rootView: SettingsView(controller: MouseController.shared)
    )
    window.delegate = self
    window.center()
    settingsWindow = window
    return window
  }

  func windowWillClose(_ notification: Notification) {
    guard let window = notification.object as? NSWindow, window === settingsWindow else { return }
    NSApp.setActivationPolicy(.accessory)
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard !terminationPrepared else { return .terminateNow }
    Task {
      await MouseController.shared.shutdown()
      terminationPrepared = true
      sender.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
  }
}
