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
    interpreter = ControlEventInterpreter(configuration: configuration)
    self.postAction = postAction
    self.postDesktopSwipe = postDesktopSwipe
  }

  public func update(configuration: MXMasterConfiguration) {
    lock.lock()
    let cancellation = interpreter.cancelPendingGesture()
    interpreter = ControlEventInterpreter(configuration: configuration)
    lock.unlock()
    dispatch(cancellation)
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
    guard let shortcut = shortcut(for: action) else { return }
    if action == .missionControl {
      openMissionControl()
      return
    }

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
    logger.info("Posting mouse action: \(action.rawValue, privacy: .public)")
    keyDown.post(tap: .cghidEventTap)
    keyUp.post(tap: .cghidEventTap)
    for event in modifierEvents.reversed() {
      activeFlags.remove(event.flag)
      event.up.flags = activeFlags
      event.up.post(tap: .cghidEventTap)
    }
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

  static func modifierKeys(for flags: CGEventFlags) -> [(
    keyCode: CGKeyCode, flag: CGEventFlags
  )] {
    var keys: [(CGKeyCode, CGEventFlags)] = []
    if flags.contains(.maskControl) { keys.append((59, .maskControl)) }
    if flags.contains(.maskCommand) { keys.append((55, .maskCommand)) }
    return keys
  }

  private static func openMissionControl() {
    let url = URL(fileURLWithPath: "/System/Applications/Mission Control.app")
    let configuration = NSWorkspace.OpenConfiguration()
    DispatchQueue.main.async {
      NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
        if let error {
          logger.error(
            "Mission Control launch failed: \(error.localizedDescription, privacy: .public)")
        } else {
          logger.info("Opened Mission Control")
        }
      }
    }
  }
}
