/// How Back and Forward reach the frontmost app. No single method works everywhere: ⌘[ indents
/// text in Notes, and VS Code ignores a page swipe. This table follows Mac Mouse Fix's per-app
/// survey ("Universal Back and Forward", August 2025).
public enum NavigationMethod: Equatable, Sendable {
  /// Mouse buttons 4 and 5. Browsers, Electron and most cross-platform apps handle them.
  case mouseButton
  /// The trackpad's page swipe. AppKit apps handle it, and apps that do not simply ignore it.
  case pageSwipe
  /// ⌘[ and ⌘].
  case commandBracket
  /// ⌥⌘[ and ⌥⌘], where ⌘[ edits text.
  case optionCommandBracket
  /// ⌘← and ⌘→.
  case commandArrow
}

public enum NavigationRouting {
  /// Prefix matches, so beta and canary builds share their app's entry.
  private static let overrides: [(prefix: String, method: NavigationMethod)] = [
    ("com.operasoftware.Opera", .pageSwipe),
    ("com.binarynights.ForkLift", .pageSwipe),
    ("org.zotero.zotero", .commandBracket),
    ("dev.warp.Warp", .commandBracket),
    ("com.adobe.Acrobat.Pro", .commandArrow),
    ("com.apple.systempreferences", .commandBracket),
    ("com.apple.AppStore", .commandBracket),
    ("com.apple.Music", .commandBracket),
    ("com.apple.AddressBook", .commandBracket),
    ("com.apple.TV", .commandBracket),
    ("com.apple.iBooksX", .commandBracket),
    ("com.apple.Preview", .commandBracket),
    ("com.apple.iCal", .commandArrow),
    ("com.apple.Notes", .optionCommandBracket),
    ("com.apple.freeform", .optionCommandBracket),
  ]

  public static func method(forBundleIdentifier bundleIdentifier: String?) -> NavigationMethod {
    guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return .mouseButton }
    if let match = overrides.first(where: { bundleIdentifier.hasPrefix($0.prefix) }) {
      return match.method
    }
    return bundleIdentifier.hasPrefix("com.apple.") ? .pageSwipe : .mouseButton
  }
}
