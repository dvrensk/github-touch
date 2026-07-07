import AppKit
import GitHubTouchCore
import SwiftUI

struct MenuContentView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if state.gh == nil {
            Text("gh CLI not found")
            Text("Install it with: brew install gh")
        } else if state.vaultCorrupt {
            Text("Vault file is unreadable")
            Button("Reset Vault…") { state.resetVault() }
        } else {
            header
            Divider()
            tokenRows
            Divider()
            if state.activation.isActive {
                Button("Deactivate Now") { state.deactivate() }
            }
            Button("Add Token…") { open(windowId: "add-token") }
            if !state.tokens.isEmpty {
                Button("Manage Tokens…") { open(windowId: "manage-tokens") }
            }
            Divider()
            Button("Quit GitHub Touch") { NSApp.terminate(nil) }
        }
    }

    @ViewBuilder private var header: some View {
        if let active = state.activeToken {
            Text("Active: \(active.label) — until midnight")
        } else {
            Text("No token active")
        }
    }

    @ViewBuilder private var tokenRows: some View {
        if state.tokens.isEmpty {
            Text("No tokens in the vault yet")
        }
        ForEach(state.tokens) { token in
            Button {
                state.activate(token)
            } label: {
                if token.isExpired() {
                    Text("\(token.label) — expired")
                } else {
                    Text("\(token.label)  (\(token.permissionSummary))")
                }
            }
            .disabled(token.isExpired() || token.id == state.activation.activeTokenId)
        }
    }

    private func open(windowId: String) {
        openWindow(id: windowId)
        NSApp.activate(ignoringOtherApps: true)
    }
}
