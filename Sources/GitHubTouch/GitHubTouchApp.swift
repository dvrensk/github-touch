import SwiftUI

struct GitHubTouchApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView().environmentObject(state)
        } label: {
            Image(systemName: "touchid")
                .opacity(state.activation.isActive ? 1.0 : 0.45)
        }
        Window("Add Token", id: "add-token") {
            AddTokenView().environmentObject(state)
        }
        .windowResizability(.contentSize)
        Window("Manage Tokens", id: "manage-tokens") {
            Text("Manage — coming in Task 10").padding().frame(width: 300)
        }
        .windowResizability(.contentSize)
        Window("Import Token", id: "import-token") {
            ImportTokenView().environmentObject(state)
        }
        .windowResizability(.contentSize)
    }
}
