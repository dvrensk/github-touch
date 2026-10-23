import AppKit
import GitHubTouchCore
import SwiftUI

extension TokenTag {
    var color: Color {
        switch self {
        case .green: return .green
        case .orange: return .orange
        case .red: return .red
        }
    }

    var nsColor: NSColor {
        switch self {
        case .green: return .systemGreen
        case .orange: return .systemOrange
        case .red: return .systemRed
        }
    }

    var displayName: String { rawValue.capitalized }

    /// A small filled circle drawn in the tag colour. Non-template, because
    /// menus render template images and SF Symbols monochrome.
    var dot: NSImage {
        let size = NSSize(width: 10, height: 10)
        let image = NSImage(size: size, flipped: false) { rect in
            self.nsColor.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}
