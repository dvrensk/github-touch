import GitHubTouchCore
import SwiftUI

struct ManageView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        List(state.tokens) { token in
            TokenRowEditor(token: token)
        }
        // Opens tall enough for every token but never taller than the screen;
        // resizable down to a scrolling list for smaller displays.
        .frame(minWidth: 520, idealWidth: 520, minHeight: 200,
               idealHeight: min(max(200, CGFloat(state.tokens.count) * 180), Self.maxIdealHeight))
    }

    private static var maxIdealHeight: CGFloat {
        (NSScreen.main?.visibleFrame.height ?? 800) - 80
    }
}

private struct TokenRowEditor: View {
    @EnvironmentObject var state: AppState
    let token: TokenEntry
    @State private var label: String
    @State private var permissionsText: String
    @State private var notes: String
    @State private var summaryText: String
    @State private var confirmingDelete = false

    init(token: TokenEntry) {
        self.token = token
        _label = State(initialValue: token.label)
        _permissionsText = State(initialValue: token.permissions.joined(separator: "; "))
        _notes = State(initialValue: token.notes)
        _summaryText = State(initialValue: token.summary ?? "")
    }

    private var dirty: Bool {
        label != token.label
            || permissionsText != token.permissions.joined(separator: "; ")
            || notes != token.notes
            || summaryText != (token.summary ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Label", text: $label).font(.headline)
                Text(token.kind.displayName).foregroundStyle(.secondary)
                if token.isExpired() {
                    Text("expired").foregroundStyle(.red)
                } else if let expiry = token.expiresAt {
                    Text("expires \(expiry.formatted(date: .abbreviated, time: .omitted))")
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Picker("Tag", selection: Binding(
                    get: { token.tag },
                    set: { state.setTag(id: token.id, tag: $0) })) {
                    Text("None").tag(TokenTag?.none)
                    ForEach(TokenTag.allCases, id: \.self) { tag in
                        Label { Text(tag.displayName) } icon: { Image(nsImage: tag.dot) }
                            .labelStyle(.titleAndIcon)
                            .tag(TokenTag?.some(tag))
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                Spacer()
                Toggle("Default", isOn: Binding(
                    get: { state.defaultTokenId == token.id },
                    set: { state.setDefault(id: $0 ? token.id : nil) }))
            }
            TextField("Menu summary", text: $summaryText)
            TextField("Permissions (semicolon-separated)", text: $permissionsText)
            TextField("Notes", text: $notes)
            HStack {
                Button("Delete…", role: .destructive) { confirmingDelete = true }
                    .confirmationDialog("Delete \"\(token.label)\" from the vault?",
                                        isPresented: $confirmingDelete) {
                        Button("Delete", role: .destructive) { state.deleteToken(id: token.id) }
                    } message: {
                        Text("The token itself keeps working on GitHub until you revoke it there.")
                    }
                Button("Copy Token") { state.copyToClipboard(token) }
                    .help("Touch ID, then the token is on the clipboard for 1 minute.")
                Spacer()
                Button("Save Changes") {
                    let permissions = permissionsText.split(separator: ";")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    let trimmedSummary = summaryText.trimmingCharacters(in: .whitespaces)
                    state.updateMetadata(id: token.id, label: label,
                                         permissions: permissions,
                                         summary: trimmedSummary.isEmpty ? nil : trimmedSummary,
                                         notes: notes)
                }
                .disabled(!dirty)
            }
        }
        .padding(.vertical, 8)
    }
}
