import SwiftUI

struct GitHubTouchApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView().environmentObject(state)
        } label: {
            MenuBarIcon(active: state.activation.isActive)
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

    var body: some View {
        if let path = Bundle.main.path(forResource: "MenuIconTemplate", ofType: "png"),
           let image = NSImage(contentsOfFile: path) {
            let _ = { image.isTemplate = true }()
            Image(nsImage: image).opacity(active ? 1.0 : 0.45)
        } else {
            // dev runs from the bare binary have no bundle resources
            Image(systemName: "touchid").opacity(active ? 1.0 : 0.45)
        }
    }
}
