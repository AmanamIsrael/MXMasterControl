import AppKit

/// The menu bar glyph: the app icon's MX Master outline as a template image, so the
/// menu bar tints it like an SF Symbol. The outline matches
/// Resources/AppIcon.icon/Assets/2-body.svg, in that file's 1024-point coordinates.
@MainActor
enum MenuBarIcon {
  /// Solid body with the scroll-wheel slot cut out.
  static let filled = makeImage(filled: true)
  /// Outlined body with a solid scroll wheel.
  static let outlined = makeImage(filled: false)

  private static let canvas: CGFloat = 18
  // The outline spans x 244...756 and y 134...894 in icon coordinates.
  private static let scale: CGFloat = 16 / 760
  private static let origin = CGPoint(x: canvas / 2 - 500 * scale, y: 1 - 134 * scale)

  private static func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
    CGPoint(x: origin.x + x * scale, y: origin.y + y * scale)
  }

  private static func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
    CGRect(origin: point(x, y), size: CGSize(width: width * scale, height: height * scale))
  }

  private static func bodyPath() -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: point(548, 134))
    path.curve(to: point(726, 298), controlPoint1: point(642, 134), controlPoint2: point(710, 196))
    path.curve(to: point(744, 694), controlPoint1: point(744, 414), controlPoint2: point(756, 570))
    path.curve(to: point(520, 894), controlPoint1: point(732, 818), controlPoint2: point(644, 894))
    path.curve(to: point(266, 768), controlPoint1: point(396, 894), controlPoint2: point(296, 852))
    path.curve(to: point(292, 596), controlPoint1: point(244, 704), controlPoint2: point(258, 640))
    path.curve(to: point(360, 430), controlPoint1: point(328, 548), controlPoint2: point(352, 500))
    path.curve(to: point(548, 134), controlPoint1: point(372, 290), controlPoint2: point(432, 134))
    path.close()
    return path
  }

  private static func makeImage(filled: Bool) -> NSImage {
    let image = NSImage(size: NSSize(width: canvas, height: canvas), flipped: true) { _ in
      NSColor.black.set()
      let body = bodyPath()
      // The wheel is wider than in the app icon so it survives at menu bar size.
      if filled {
        body.append(
          NSBezierPath(roundedRect: rect(522, 206, 76, 176), xRadius: 38 * scale, yRadius: 38 * scale))
        body.windingRule = .evenOdd
        body.fill()
      } else {
        body.lineWidth = 1.3
        body.stroke()
        NSBezierPath(roundedRect: rect(530, 214, 60, 160), xRadius: 30 * scale, yRadius: 30 * scale)
          .fill()
      }
      return true
    }
    image.isTemplate = true
    return image
  }
}
