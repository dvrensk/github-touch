import AppKit
import GitHubTouchCore
import SwiftUI

extension TokenTag {
    var color: Color { Color(nsColor: nsColor) }

    /// A muted green (systemGreen reads as toy-like next to the others);
    /// orange and red stay the system colours.
    var nsColor: NSColor {
        switch self {
        case .green: return NSColor(srgbRed: 0.24, green: 0.62, blue: 0.30, alpha: 1)
        case .orange: return .systemOrange
        case .red: return .systemRed
        }
    }

    var displayName: String { rawValue.capitalized }

    /// A filled circle in the tag colour for menu rows. Non-template, so the
    /// menu draws it in colour rather than as a monochrome glyph.
    var dot: NSImage {
        let image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            self.nsColor.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}
