import CoreFoundation
import MXMasterCore

/// Reads whether the trackpad gestures for Mission Control and App Exposé are turned on, in
/// System Settings → Trackpad → More Gestures. The Dock ignores a synthetic swipe toward a
/// gesture that is off, so such a swipe must fire the action as a single shortcut instead.
enum DockGestureSettings {
  private static let domain = "com.apple.dock"

  static func isEnabled(_ action: MouseAction) -> Bool {
    let key: String
    let defaultValue: Bool
    switch action {
    case .missionControl:
      key = "showMissionControlGestureEnabled"
      defaultValue = true
    case .appExpose:
      key = "showAppExposeGestureEnabled"
      defaultValue = false
    default:
      return true
    }
    // The Dock owns this domain. Synchronizing drops the cached copy, so a change made in
    // System Settings applies to the next swipe.
    CFPreferencesAppSynchronize(domain as CFString)
    var exists: DarwinBoolean = false
    let value = CFPreferencesGetAppBooleanValue(key as CFString, domain as CFString, &exists)
    return exists.boolValue ? value : defaultValue
  }
}
