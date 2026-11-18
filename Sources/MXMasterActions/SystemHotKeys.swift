import CoreGraphics
import Foundation
import OSLog

/// A macOS feature that System Settings → Keyboard → Keyboard Shortcuts can bind. WindowServer
/// calls these "symbolic hot keys" and identifies each one by a number.
enum SystemHotKey: Int32, CaseIterable, Sendable {
  case missionControl = 32
  case appExpose = 33
  case showDesktop = 36
  case moveLeftASpace = 79
  case moveRightASpace = 81
}

/// Triggers a system feature by posting the keyboard shortcut that is bound to it right now.
///
/// The bindings come from WindowServer, not from a table of defaults, so a feature still works
/// after the user changes its shortcut. When the user turned the shortcut off, the feature is
/// bound to a key code no keyboard can produce, for this session only, and that key is posted
/// instead. The user's real keys and saved shortcuts stay as they are. This follows Mac Mouse Fix's approach. The functions are private, so
/// they are looked up at runtime; without them, nothing is posted and an error is logged.
enum SystemHotKeys {
  private static let logger = Logger(
    subsystem: "com.amanamisrael.MXMasterControl",
    category: "actions"
  )

  /// No key equivalent or key code is set.
  static let unset: UInt16 = 0xFFFF
  /// Key codes from real keyboards stay below 0x80. Offsetting by the hot key number keeps
  /// each private binding unique.
  static let unreachableKeyCodeBase: UInt16 = 400
  /// Keypad and fn together never come from a single physical key press.
  static let unreachableFlags: CGEventFlags = [.maskNumericPad, .maskSecondaryFn]

  struct Binding: Equatable {
    let keyCode: CGKeyCode
    let flags: CGEventFlags
  }

  /// The shortcut to post for a hot key's current state, or `nil` when there is none to use.
  /// A binding with a key equivalent matches by character; its key code is the one recorded
  /// for the layout the user had when they set it.
  static func usableBinding(
    enabled: Bool, keyCode: UInt16, modifiers: UInt64
  ) -> Binding? {
    guard enabled, keyCode != unset else { return nil }
    return Binding(keyCode: keyCode, flags: CGEventFlags(rawValue: modifiers))
  }

  static func unreachableBinding(for hotKey: SystemHotKey) -> Binding {
    Binding(
      keyCode: unreachableKeyCodeBase + UInt16(hotKey.rawValue), flags: unreachableFlags)
  }

  /// The binding to post for `hotKey`. If the user turned it off, it is first rebound to an
  /// unreachable key and enabled. Returns `nil` when WindowServer cannot be reached.
  static func binding(for hotKey: SystemHotKey) -> Binding? {
    guard let api = WindowServerHotKeys.shared else {
      logger.error("Symbolic hot key API unavailable; system action skipped")
      return nil
    }
    if let binding = api.currentBinding(hotKey) { return binding }

    // WindowServer keeps this change in memory for the session only; the user's saved
    // shortcuts are not touched. It may also drop flags it does not store, so the binding is
    // read back rather than assumed.
    let fallback = unreachableBinding(for: hotKey)
    let writeError = api.setValue(
      hotKey.rawValue, unset, fallback.keyCode, fallback.flags.rawValue)
    let enableError = api.setEnabled(hotKey.rawValue, true)
    guard writeError == 0, enableError == 0, let binding = api.currentBinding(hotKey) else {
      logger.error(
        "Could not bind hot key \(hotKey.rawValue, privacy: .public): \(writeError, privacy: .public)/\(enableError, privacy: .public)"
      )
      return nil
    }
    return binding
  }
}

/// The SkyLight hot key functions, resolved once.
private struct WindowServerHotKeys {
  typealias GetValue = @convention(c) (
    Int32, UnsafeMutablePointer<UInt16>, UnsafeMutablePointer<UInt16>, UnsafeMutablePointer<UInt64>
  ) -> Int32
  typealias SetValue = @convention(c) (Int32, UInt16, UInt16, UInt64) -> Int32
  typealias IsEnabled = @convention(c) (Int32) -> Bool
  typealias SetEnabled = @convention(c) (Int32, Bool) -> Int32

  let getValue: GetValue
  let setValue: SetValue
  let isEnabled: IsEnabled
  let setEnabled: SetEnabled

  static let shared: WindowServerHotKeys? = {
    guard
      let handle = dlopen(nil, RTLD_NOW),
      let getValue = dlsym(handle, "CGSGetSymbolicHotKeyValue"),
      let setValue = dlsym(handle, "CGSSetSymbolicHotKeyValue"),
      let isEnabled = dlsym(handle, "CGSIsSymbolicHotKeyEnabled"),
      let setEnabled = dlsym(handle, "CGSSetSymbolicHotKeyEnabled")
    else { return nil }
    return WindowServerHotKeys(
      getValue: unsafeBitCast(getValue, to: GetValue.self),
      setValue: unsafeBitCast(setValue, to: SetValue.self),
      isEnabled: unsafeBitCast(isEnabled, to: IsEnabled.self),
      setEnabled: unsafeBitCast(setEnabled, to: SetEnabled.self)
    )
  }()

  func currentBinding(_ hotKey: SystemHotKey) -> SystemHotKeys.Binding? {
    var keyEquivalent: UInt16 = 0
    var keyCode: UInt16 = 0
    var modifiers: UInt64 = 0
    guard getValue(hotKey.rawValue, &keyEquivalent, &keyCode, &modifiers) == 0 else { return nil }
    return SystemHotKeys.usableBinding(
      enabled: isEnabled(hotKey.rawValue), keyCode: keyCode, modifiers: modifiers)
  }
}
