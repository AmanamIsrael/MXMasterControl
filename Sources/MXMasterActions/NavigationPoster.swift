import AppKit
import CoreGraphics
import MXMasterCore

/// Posts Back or Forward in the way the frontmost app understands. See `NavigationRouting`.
enum NavigationPoster {
  enum Direction: Equatable, Sendable {
    case back
    case forward
  }

  /// What a method posts for a direction. Shortcuts go through the dispatcher's key posting.
  enum Output: Equatable {
    case mouseButton(CGMouseButton)
    case pageSwipe(Direction)
    case shortcut(MouseKeyboardShortcut)
  }

  static func output(for method: NavigationMethod, direction: Direction) -> Output {
    let back = direction == .back
    switch method {
    case .mouseButton:
      // Button numbers count from 0, so buttons 4 and 5 are 3 and 4.
      return .mouseButton(CGMouseButton(rawValue: back ? 3 : 4)!)
    case .pageSwipe:
      return .pageSwipe(direction)
    case .commandBracket:
      return .shortcut(MouseKeyboardShortcut(keyCode: back ? 33 : 30, flags: .maskCommand))
    case .optionCommandBracket:
      return .shortcut(
        MouseKeyboardShortcut(keyCode: back ? 33 : 30, flags: [.maskCommand, .maskAlternate]))
    case .commandArrow:
      return .shortcut(MouseKeyboardShortcut(keyCode: back ? 123 : 124, flags: .maskCommand))
    }
  }

  static func frontmostOutput(for direction: Direction) -> Output {
    let bundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    return output(
      for: NavigationRouting.method(forBundleIdentifier: bundleIdentifier), direction: direction)
  }

  static func postMouseButton(_ button: CGMouseButton) {
    let location = CGEvent(source: nil)?.location ?? .zero
    let source = CGEventSource(stateID: .hidSystemState)
    for type in [CGEventType.otherMouseDown, .otherMouseUp] {
      CGEvent(
        mouseEventSource: source, mouseType: type, mouseCursorPosition: location,
        mouseButton: button
      )?.post(tap: .cghidEventTap)
    }
  }

  /// The trackpad's page swipe: a gesture event of the navigation-swipe subtype, began with a
  /// direction, then ended. The fields are undocumented; Mac Mouse Fix and SensibleSideButtons
  /// use the same encoding.
  static func postPageSwipe(_ direction: Direction) {
    guard
      let gestureType = CGEventType(rawValue: 29),
      let subtype = CGEventField(rawValue: 110),
      let phase = CGEventField(rawValue: 132),
      let swipeDirection = CGEventField(rawValue: 115),
      let event = CGEvent(source: nil)
    else { return }
    // kIOHIDEventTypeNavigationSwipe, and IOHIDSwipeMask left (back) or right (forward).
    let navigationSwipe: Int64 = 16
    let began: Int64 = 1
    let ended: Int64 = 4
    event.type = gestureType
    event.setIntegerValueField(subtype, value: navigationSwipe)
    event.setIntegerValueField(phase, value: began)
    event.setIntegerValueField(swipeDirection, value: direction == .back ? 4 : 8)
    event.post(tap: .cgSessionEventTap)
    event.setIntegerValueField(swipeDirection, value: 0)
    event.setIntegerValueField(phase, value: ended)
    event.post(tap: .cgSessionEventTap)
  }
}
