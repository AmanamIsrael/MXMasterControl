import MXMasterCore
import Testing

@Test func appleAppsGetAPageSwipeThatOtherAppsIgnore() {
  #expect(NavigationRouting.method(forBundleIdentifier: "com.apple.Safari") == .pageSwipe)
  #expect(NavigationRouting.method(forBundleIdentifier: "com.apple.finder") == .pageSwipe)
}

@Test func otherAppsGetMouseButtonsFourAndFive() {
  #expect(NavigationRouting.method(forBundleIdentifier: "com.microsoft.VSCode") == .mouseButton)
  #expect(NavigationRouting.method(forBundleIdentifier: "com.google.Chrome") == .mouseButton)
  #expect(NavigationRouting.method(forBundleIdentifier: nil) == .mouseButton)
  #expect(NavigationRouting.method(forBundleIdentifier: "") == .mouseButton)
}

@Test func appsWhereCommandBracketEditsTextUseTheirOwnShortcut() {
  #expect(NavigationRouting.method(forBundleIdentifier: "com.apple.Notes") == .optionCommandBracket)
  #expect(NavigationRouting.method(forBundleIdentifier: "com.apple.iCal") == .commandArrow)
  #expect(NavigationRouting.method(forBundleIdentifier: "com.apple.Preview") == .commandBracket)
}

@Test func overridesMatchOtherReleaseChannels() {
  #expect(
    NavigationRouting.method(forBundleIdentifier: "com.operasoftware.OperaNext") == .pageSwipe)
}
