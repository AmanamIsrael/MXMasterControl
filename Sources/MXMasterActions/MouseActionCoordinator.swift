import AppKit
@preconcurrency import ApplicationServices
import CoreGraphics
import Foundation
import MXMasterCore
import OSLog

public final class MouseActionCoordinator: @unchecked Sendable {
  private static let logger = Logger(
    subsystem: "com.amanamisrael.MXMasterControl",
    category: "actions"
  )

  private let lock = NSLock()
  private let postAction: @Sendable (MouseAction) -> Void
  private let postDesktopSwipe: @Sendable (DesktopSwipeUpdate) -> Void
  private var interpreter: ControlEventInterpreter

  public convenience init(configuration: MXMasterConfiguration) {
    let synthesizer = DesktopSwipeSynthesizer()
    self.init(
      configuration: configuration,
      postAction: MouseActionDispatcher.post,
      postDesktopSwipe: synthesizer.post
    )
  }

  public init(
    configuration: MXMasterConfiguration,
    postAction: @escaping @Sendable (MouseAction) -> Void,
    postDesktopSwipe: @escaping @Sendable (DesktopSwipeUpdate) -> Void = { _ in }
  ) {
    interpreter = Self.interpreter(for: configuration)
    self.postAction = postAction
    self.postDesktopSwipe = postDesktopSwipe
  }

  public func update(configuration: MXMasterConfiguration) {
    lock.lock()
    let cancellation = interpreter.cancelPendingGesture()
    interpreter = Self.interpreter(for: configuration)
    lock.unlock()
    dispatch(cancellation)
  }

  private static func interpreter(for configuration: MXMasterConfiguration)
    -> ControlEventInterpreter
  {
    ControlEventInterpreter(
      configuration: configuration, isDockGestureEnabled: DockGestureSettings.isEnabled)
  }

  public func cancelPendingGesture() {
    lock.lock()
    let cancellation = interpreter.cancelPendingGesture()
    lock.unlock()
    dispatch(cancellation)
  }

  public func handle(_ event: HIDPPControlEvent) {
    lock.lock()
    let effects = interpreter.handle(event)
    lock.unlock()
    for effect in effects {
      dispatch(effect)
    }
  }

  private func dispatch(_ effect: MouseInputEffect?) {
    guard let effect else { return }
    switch effect {
    case .action(let action):
      Self.logger.info("Dispatching configured action: \(action.rawValue, privacy: .public)")
      postAction(action)
    case .desktopSwipe(let update):
      postDesktopSwipe(update)
    }
  }
}

struct MouseKeyboardShortcut: Equatable {
  let keyCode: CGKeyCode
  let flags: CGEventFlags
}

/// How an action reaches macOS.
enum MouseActionRoute: Equatable {
  /// A system feature, posted through the shortcut the user has bound to it.
  case systemHotKey(SystemHotKey)
  /// An app command with a fixed shortcut.
  case shortcut(MouseKeyboardShortcut)
}

public enum MouseActionDispatcher {
  private static let logger = Logger(
    subsystem: "com.amanamisrael.MXMasterControl",
    category: "actions"
  )

  public static var accessibilityGranted: Bool { AXIsProcessTrusted() }

  @MainActor
  public static func requestAccessibility() -> Bool {
    let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    return AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
  }

  public static func post(_ action: MouseAction) {
    switch route(for: action) {
    case nil:
      return
    case .systemHotKey(let hotKey):
      guard let binding = SystemHotKeys.binding(for: hotKey) else { return }
      logger.info("Posting mouse action: \(action.rawValue, privacy: .public)")
      post(MouseKeyboardShortcut(keyCode: binding.keyCode, flags: binding.flags))
    case .shortcut(let shortcut):
      logger.info("Posting mouse action: \(action.rawValue, privacy: .public)")
      post(shortcut)
    }
  }

  static func route(for action: MouseAction) -> MouseActionRoute? {
    switch action {
    case .systemDefault, .disabled: nil
    case .back: .shortcut(MouseKeyboardShortcut(keyCode: 33, flags: .maskCommand))
    case .forward: .shortcut(MouseKeyboardShortcut(keyCode: 30, flags: .maskCommand))
    case .missionControl: .systemHotKey(.missionControl)
    case .appExpose: .systemHotKey(.appExpose)
    case .showDesktop: .systemHotKey(.showDesktop)
    case .desktopLeft: .systemHotKey(.moveLeftASpace)
    case .desktopRight: .systemHotKey(.moveRightASpace)
    }
  }

  /// Presses the shortcut's modifier keys, the key, then releases them in reverse order, so
  /// apps that read modifier state see a real chord. Flags without a key, such as fn, ride on
  /// the key event.
  private static func post(_ shortcut: MouseKeyboardShortcut) {
    let source = CGEventSource(stateID: .hidSystemState)
    guard
      let keyDown = CGEvent(
        keyboardEventSource: source,
        virtualKey: shortcut.keyCode,
        keyDown: true
      ),
      let keyUp = CGEvent(
        keyboardEventSource: source,
        virtualKey: shortcut.keyCode,
        keyDown: false
      )
    else { return }

    let modifierEvents = modifierKeys(for: shortcut.flags).compactMap {
      modifier -> (
        down: CGEvent, up: CGEvent, flag: CGEventFlags
      )? in
      guard
        let down = CGEvent(
          keyboardEventSource: source,
          virtualKey: modifier.keyCode,
          keyDown: true
        ),
        let up = CGEvent(
          keyboardEventSource: source,
          virtualKey: modifier.keyCode,
          keyDown: false
        )
      else { return nil }
      return (down, up, modifier.flag)
    }

    var activeFlags: CGEventFlags = []
    for event in modifierEvents {
      activeFlags.insert(event.flag)
      event.down.flags = activeFlags
      event.down.post(tap: .cghidEventTap)
    }
    keyDown.flags = shortcut.flags
    keyUp.flags = shortcut.flags
    keyDown.post(tap: .cghidEventTap)
    keyUp.post(tap: .cghidEventTap)
    for event in modifierEvents.reversed() {
      activeFlags.remove(event.flag)
      event.up.flags = activeFlags
      event.up.post(tap: .cghidEventTap)
    }
  }

  static func modifierKeys(for flags: CGEventFlags) -> [(
    keyCode: CGKeyCode, flag: CGEventFlags
  )] {
    let keys: [(CGKeyCode, CGEventFlags)] = [
      (59, .maskControl), (58, .maskAlternate), (56, .maskShift), (55, .maskCommand),
    ]
    return keys.filter { flags.contains($0.1) }
  }
}
