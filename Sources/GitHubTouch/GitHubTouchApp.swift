import GitHubTouchCore
import SwiftUI

struct GitHubTouchApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView().environmentObject(state)
        } label: {
            MenuBarIcon(active: state.activation.isActive,
                        tag: state.activeToken?.tag,
                        countdown: state.activation.countdownText(now: state.now))
        }
        Window("Add Token", id: "add-token") {
            AddTokenView().environmentObject(state)
        }
        .windowResizability(.contentSize)
        Window("Manage Tokens", id: "manage-tokens") {
            ManageView().environmentObject(state)
        }
        .windowResizability(.contentSize)
        Window("Import Token", id: "import-token") {
            ImportTokenView().environmentObject(state)
        }
        .windowResizability(.contentSize)
    }
}

struct MenuBarIcon: View {
    let active: Bool
    let tag: TokenTag?
    let countdown: String?

    var body: some View {
        HStack(spacing: 3) {
            icon
            if let countdown { Text(countdown) }
        }
    }

    @ViewBuilder private var icon: some View {
        if let path = Bundle.main.path(forResource: "MenuIconTemplate", ofType: "png"),
           let image = NSImage(contentsOfFile: path) {
            if active, let tag {
                Image(nsImage: Self.tinted(image, with: tag.nsColor))
            } else {
                let _ = { image.isTemplate = true }()
                Image(nsImage: image).opacity(active ? 1.0 : 0.45)
            }
        } else {
            // dev runs from the bare binary have no bundle resources
            Image(systemName: "touchid")
                .foregroundStyle(active ? (tag?.color ?? .primary) : .primary)
                .opacity(active ? 1.0 : 0.45)
        }
    }

    /// Template images always draw monochrome, so a coloured state needs a
    /// non-template copy: the glyph's alpha filled with the tag colour.
    static func tinted(_ template: NSImage, with color: NSColor) -> NSImage {
        let image = NSImage(size: template.size, flipped: false) { rect in
            template.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        image.isTemplate = false
        return image
    }
}
