import AppKit
import GitHubTouchCore
import SwiftUI

struct MenuContentView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            content
        }
        .onAppear { state.refreshGhLoginState() }
    }

    @ViewBuilder private var content: some View {
        if state.gh == nil {
            Text("gh CLI not found")
            Text("Install it with: brew install gh")
        } else if state.vaultCorrupt {
            Text("Vault file is unreadable")
            Button("Reset Vault…") { state.resetVault() }
        } else {
            header
            if state.canImportExistingToken {
                Button("Import current gh token…") { open(windowId: "import-token") }
            }
            Divider()
            tokenRows
            Divider()
            if let extendTitle {
                Button(extendTitle) { state.extend() }
            }
            if state.canSwitchToDefault {
                Button("Switch to Default Now") { state.switchToDefaultNow() }
            }
            if state.activation.isActive {
                Button("Deactivate Now") { state.deactivate() }
            }
            Picker("Duration", selection: $state.duration) {
                ForEach(ActivationDuration.allCases, id: \.self) { duration in
                    Text(duration.menuTitle).tag(duration)
                }
            }
            .pickerStyle(.menu)
            Divider()
            Button("Add Token…") { open(windowId: "add-token") }
            if !state.tokens.isEmpty {
                Button("Manage Tokens…") { open(windowId: "manage-tokens") }
            }
            Divider()
            LaunchAtLoginToggle()
            #if DEBUG
            Button("Debug: Clear in 1 Minute") {
                var s = state.activation
                s.clearAt = Date(timeIntervalSinceNow: 60)
                state.activation = s
                state.stateStore.save(s)
                state.scheduleClear(at: s.clearAt!)
            }
            #endif
            Button("Quit GitHub Touch") { NSApp.terminate(nil) }
        }
    }

    @ViewBuilder private var header: some View {
        if let active = state.activeToken {
            let activation = state.activation
            if let clearAt = activation.clearAt {
                if activation.untilMidnight {
                    Text("Active: \(active.label) — until midnight")
                } else {
                    let minutes = max(0, Int((clearAt.timeIntervalSince(state.now) / 60).rounded(.up)))
                    Text("Active: \(active.label) — \(minutes) min left (until \(clearAt.formatted(date: .omitted, time: .shortened)))")
                }
            } else {
                Text("Active: \(active.label) (default)")
            }
        } else {
            Text("No token active")
        }
    }

    /// "Add 30 min" / "Keep Until Midnight" while a timed token runs; nil when
    /// extending would change nothing or no timer is running.
    private var extendTitle: String? {
        let activation = state.activation
        guard activation.isActive, activation.clearAt != nil else { return nil }
        if state.duration == .untilMidnight {
            return activation.untilMidnight ? nil : "Keep Until Midnight"
        }
        return "Add \(state.duration.menuTitle)"
    }

    @ViewBuilder private var tokenRows: some View {
        if state.tokens.isEmpty {
            Text("No tokens in the vault yet")
        } else {
            // A section header keeps the Duration visible where the token is picked.
            Section(state.duration.activationPhrase) {
                ForEach(state.tokens.sortedByTag()) { token in
                    Button {
                        state.activate(token)
                    } label: {
                        let suffix = token.id == state.defaultTokenId ? " — default" : ""
                        let text = token.isExpired()
                            ? "\(token.label) — expired\(suffix)"
                            : "\(token.label)  (\(token.menuSummary))\(suffix)"
                        if let tag = token.tag {
                            Label { Text(text) } icon: { Image(nsImage: tag.dot) }
                                .labelStyle(.titleAndIcon)
                        } else {
                            Text(text)
                        }
                    }
                    .disabled(token.isExpired() || token.id == state.activation.activeTokenId)
                }
            }
        }
    }

    private func open(windowId: String) {
        openWindow(id: windowId)
        NSApp.activate(ignoringOtherApps: true)
    }
}
