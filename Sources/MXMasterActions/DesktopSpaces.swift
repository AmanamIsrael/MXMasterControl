import ColorSync
import CoreGraphics
import Foundation

/// Reads the Spaces that WindowServer manages for each display. There is no public API for
/// this, so the SkyLight functions are looked up at runtime. If they are missing, callers get
/// `nil` and fall back to their default.
enum DesktopSpaces {
  private typealias MainConnection = @convention(c) () -> Int32
  private typealias CopyManagedDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?

  private static let functions: (MainConnection, CopyManagedDisplaySpaces)? = {
    guard
      let skyLight = dlopen(
        "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW),
      let connection = dlsym(skyLight, "SLSMainConnectionID"),
      let copySpaces = dlsym(skyLight, "SLSCopyManagedDisplaySpaces")
    else { return nil }
    return (
      unsafeBitCast(connection, to: MainConnection.self),
      unsafeBitCast(copySpaces, to: CopyManagedDisplaySpaces.self)
    )
  }()

  /// The number of Spaces on `display`, full-screen apps included, since a swipe passes
  /// through them too.
  static func count(onDisplay display: CGDirectDisplayID) -> Int? {
    guard
      let (connection, copySpaces) = functions,
      let entries = copySpaces(connection())?.takeRetainedValue() as? [[String: Any]],
      let uuid = CGDisplayCreateUUIDFromDisplayID(display)?.takeRetainedValue(),
      let identifier = CFUUIDCreateString(nil, uuid) as String?
    else { return nil }
    return count(in: entries, displayIdentifier: identifier)
  }

  /// With "Displays have separate Spaces" turned off, WindowServer reports a single entry
  /// named "Main" for every display, so that entry is the fallback.
  static func count(in entries: [[String: Any]], displayIdentifier: String) -> Int? {
    let entry =
      entries.first { ($0["Display Identifier"] as? String) == displayIdentifier }
      ?? (entries.count == 1 ? entries.first : nil)
    return (entry?["Spaces"] as? [Any])?.count
  }
}
