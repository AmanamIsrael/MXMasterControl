@preconcurrency import ApplicationServices
import CoreGraphics
import Foundation
import MXMasterCore

final class MouseActionCoordinator: @unchecked Sendable {
  private let lock = NSLock()
  private var interpreter: ControlEventInterpreter

  init(configuration: MXMasterConfiguration) {
    interpreter = ControlEventInterpreter(configuration: configuration)
  }

  func update(configuration: MXMasterConfiguration) {
    lock.lock()
    interpreter = ControlEventInterpreter(configuration: configuration)
    lock.unlock()
  }

  func handle(_ event: HIDPPControlEvent) {
    lock.lock()
    let actions = interpreter.handle(event)
    lock.unlock()
    actions.forEach(MouseActionDispatcher.post)
  }
}

enum MouseActionDispatcher {
  static var accessibilityGranted: Bool { AXIsProcessTrusted() }

  @MainActor
  static func requestAccessibility() -> Bool {
    let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    return AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
  }

  static func post(_ action: MouseAction) {
    guard let shortcut = shortcut(for: action) else { return }
    guard
      let keyDown = CGEvent(
        keyboardEventSource: nil,
        virtualKey: shortcut.keyCode,
        keyDown: true
      ),
      let keyUp = CGEvent(
        keyboardEventSource: nil,
        virtualKey: shortcut.keyCode,
        keyDown: false
      )
    else { return }

    keyDown.flags = shortcut.flags
    keyUp.flags = shortcut.flags
    keyDown.post(tap: .cghidEventTap)
    keyUp.post(tap: .cghidEventTap)
  }

  private static func shortcut(for action: MouseAction) -> (
    keyCode: CGKeyCode, flags: CGEventFlags
  )? {
    switch action {
    case .systemDefault, .disabled: nil
    case .back: (33, .maskCommand)
    case .forward: (30, .maskCommand)
    case .missionControl: (126, .maskControl)
    case .appExpose: (125, .maskControl)
    case .showDesktop: (103, [])
    case .desktopLeft: (123, .maskControl)
    case .desktopRight: (124, .maskControl)
    }
  }
}
