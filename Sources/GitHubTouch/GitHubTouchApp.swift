import SwiftUI

struct GitHubTouchApp: App {
    var body: some Scene {
        MenuBarExtra("GitHub Touch", systemImage: "touchid") {
            Text("GitHub Touch — under construction")
            Divider()
            Button("Quit") { NSApp.terminate(nil) }
        }
    }
}
