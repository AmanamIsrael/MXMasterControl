@preconcurrency import ApplicationServices
import CoreGraphics
import Foundation
import MXMasterCore

public final class MouseActionCoordinator: @unchecked Sendable {
  private let lock = NSLock()
  private let postAction: @Sendable (MouseAction) -> Void
  private var interpreter: ControlEventInterpreter

  public convenience init(configuration: MXMasterConfiguration) {
    self.init(configuration: configuration, postAction: MouseActionDispatcher.post)
  }

  public init(
    configuration: MXMasterConfiguration,
    postAction: @escaping @Sendable (MouseAction) -> Void
  ) {
    interpreter = ControlEventInterpreter(configuration: configuration)
    self.postAction = postAction
  }

  public func update(configuration: MXMasterConfiguration) {
    lock.lock()
    interpreter = ControlEventInterpreter(configuration: configuration)
    lock.unlock()
  }

  public func handle(_ event: HIDPPControlEvent) {
    lock.lock()
    let actions = interpreter.handle(event)
    lock.unlock()
    actions.forEach(postAction)
  }
}

struct MouseKeyboardShortcut: Equatable {
  let keyCode: CGKeyCode
  let flags: CGEventFlags
}

public enum MouseActionDispatcher {
  public static var accessibilityGranted: Bool { AXIsProcessTrusted() }

  @MainActor
  public static func requestAccessibility() -> Bool {
    let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    return AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
  }

  public static func post(_ action: MouseAction) {
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

  static func shortcut(for action: MouseAction) -> MouseKeyboardShortcut? {
    switch action {
    case .systemDefault, .disabled: nil
    case .back: MouseKeyboardShortcut(keyCode: 33, flags: .maskCommand)
    case .forward: MouseKeyboardShortcut(keyCode: 30, flags: .maskCommand)
    case .missionControl: MouseKeyboardShortcut(keyCode: 126, flags: .maskControl)
    case .appExpose: MouseKeyboardShortcut(keyCode: 125, flags: .maskControl)
    case .showDesktop: MouseKeyboardShortcut(keyCode: 103, flags: [])
    case .desktopLeft: MouseKeyboardShortcut(keyCode: 123, flags: .maskControl)
    case .desktopRight: MouseKeyboardShortcut(keyCode: 124, flags: .maskControl)
    }
  }
}
