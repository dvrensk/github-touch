import AppKit
import GitHubTouchCore
import LocalAuthentication
import LocalAuthenticationEmbeddedUI
import SwiftUI

struct ManageView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var selection: UUID?

    var body: some View {
        NavigationSplitView {
            List(state.tokens, selection: $selection) { token in
                TokenSidebarRow(token: token)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
            .toolbar {
                ToolbarItem {
                    Button {
                        openWindow(id: "add-token")
                        NSApp.activate(ignoringOtherApps: true)
                    } label: {
                        Label("Add Token", systemImage: "plus")
                    }
                    .help("Add a token")
                }
            }
        } detail: {
            if let token = state.tokens.first(where: { $0.id == selection }) {
                // A fresh editor per token, so half-typed edits don't leak across.
                TokenDetail(token: token).id(token.id)
            } else {
                Text(state.tokens.isEmpty ? "No tokens yet. Add one with +." : "Select a token")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 680, idealWidth: 780, minHeight: 440, idealHeight: 640)
        .onAppear { if selection == nil { selection = state.tokens.first?.id } }
    }
}

private struct TagDot: View {
    let tag: TokenTag?

    var body: some View {
        Circle()
            .fill(tag?.color ?? .clear)
            .overlay(Circle().strokeBorder(Color.secondary.opacity(tag == nil ? 0.5 : 0), lineWidth: 1))
            .frame(width: 9, height: 9)
    }
}

/// The system's in-window Touch ID glyph. SwiftUI's LocalAuthenticationView
/// ignores controlSize and draws it at a large fixed size; the AppKit view
/// takes a small one.
private struct TouchIDGlyph: NSViewRepresentable {
    let context: LAContext

    func makeNSView(context: Context) -> LAAuthenticationView {
        LAAuthenticationView(context: self.context, controlSize: .small)
    }

    func updateNSView(_ nsView: LAAuthenticationView, context: Context) {}
}

private struct TokenSidebarRow: View {
    @EnvironmentObject var state: AppState
    let token: TokenEntry

    var body: some View {
        HStack(spacing: 8) {
            TagDot(tag: token.tag)
            VStack(alignment: .leading, spacing: 1) {
                Text(token.label).lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(token.isExpired() ? .red : .secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if state.defaultTokenId == token.id {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Default token")
            }
        }
        .padding(.vertical, 3)
    }

    private var subtitle: String {
        if token.isExpired() { return "Expired" }
        let detail = token.summary ?? token.kind.displayName
        return state.activation.activeTokenId == token.id ? "Active · \(detail)" : detail
    }
}

private struct TokenDetail: View {
    @EnvironmentObject var state: AppState
    let token: TokenEntry
    @State private var label: String
    @State private var summaryText: String
    @State private var permissionsText: String
    @State private var notes: String
    @State private var confirmingDelete = false
    /// Set while the inline Touch ID control waits for a finger.
    @State private var copyContext: LAContext?
    @FocusState private var focused: Field?

    private enum Field { case label, summary, permissions, notes }

    init(token: TokenEntry) {
        self.token = token
        _label = State(initialValue: token.label)
        _summaryText = State(initialValue: token.summary ?? "")
        _permissionsText = State(initialValue: token.permissions.joined(separator: "; "))
        _notes = State(initialValue: token.notes)
    }

    var body: some View {
        Form {
            Section { header }

            Section {
                Toggle(isOn: Binding(
                    get: { state.defaultTokenId == token.id },
                    set: { state.setDefault(id: $0 ? token.id : nil) })) {
                    Text("Default token")
                    Text("Restored when a timed token runs out")
                }
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
            }

            Section("Details") {
                TextField("Label", text: $label)
                    .focused($focused, equals: .label)
                TextField("Menu summary", text: $summaryText, prompt: Text("Shown in the menu"))
                    .focused($focused, equals: .summary)
                TextField("Permissions", text: $permissionsText,
                          prompt: Text("Separate with semicolons"), axis: .vertical)
                    .focused($focused, equals: .permissions)
                TextField("Notes", text: $notes, prompt: Text("Optional"), axis: .vertical)
                    .lineLimit(1...6)
                    .focused($focused, equals: .notes)
            }

            Section {
                LabeledContent("Added", value: token.createdAt.formatted(date: .abbreviated, time: .omitted))
                LabeledContent("Last activated",
                               value: token.lastActivatedAt?.formatted(date: .abbreviated, time: .shortened)
                                   ?? "Never")
                LabeledContent("Expires") {
                    Text(token.expiresAt?.formatted(date: .abbreviated, time: .omitted) ?? "Never")
                        .foregroundStyle(token.isExpired() ? .red : .secondary)
                }
            }

            Section {
                Button("Delete Token…", role: .destructive) { confirmingDelete = true }
                    .confirmationDialog("Delete “\(token.label)” from the vault?",
                                        isPresented: $confirmingDelete) {
                        Button("Delete", role: .destructive) { state.deleteToken(id: token.id) }
                    } message: {
                        Text("The token itself keeps working on GitHub until you revoke it there.")
                    }
            }
        }
        .formStyle(.grouped)
        // Edits save as you leave a field, so there is no Save button to forget.
        .onSubmit(save)
        .onChange(of: focused) { _ in save() }
        .onDisappear(perform: save)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            TagDot(tag: token.tag)
            VStack(alignment: .leading, spacing: 2) {
                Text(token.label).font(.title3.weight(.semibold)).lineLimit(1)
                Text(headerSubtitle).font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            copyControl
        }
        .padding(.vertical, 4)
    }

    private var headerSubtitle: String {
        var parts = [token.kind.displayName]
        if state.activation.activeTokenId == token.id { parts.append("active now") }
        if token.isExpired() {
            parts.append("expired")
        } else if let expiry = token.expiresAt {
            parts.append("expires \(expiry.formatted(date: .abbreviated, time: .omitted))")
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var copyControl: some View {
        if let copyContext {
            HStack(spacing: 8) {
                TouchIDGlyph(context: copyContext)
                    .frame(width: 22, height: 22)
                    .task { await authenticate(with: copyContext) }
                Text("Touch ID to copy").foregroundStyle(.secondary).fixedSize()
                Button("Cancel") { copyContext.invalidate() }
            }
        } else {
            Button {
                startCopy()
            } label: {
                Label("Copy Token", systemImage: "doc.on.doc")
            }
            .disabled(token.isExpired())
            .help("Touch ID, then the token is on the clipboard for 1 minute.")
        }
    }

    private var dirty: Bool {
        label != token.label
            || permissionsText != token.permissions.joined(separator: "; ")
            || notes != token.notes
            || summaryText != (token.summary ?? "")
    }

    private func save() {
        guard dirty else { return }
        let trimmedLabel = label.trimmingCharacters(in: .whitespaces)
        if trimmedLabel.isEmpty { label = token.label }
        let permissions = permissionsText.split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let trimmedSummary = summaryText.trimmingCharacters(in: .whitespaces)
        state.updateMetadata(id: token.id, label: trimmedLabel.isEmpty ? token.label : trimmedLabel,
                             permissions: permissions,
                             summary: trimmedSummary.isEmpty ? nil : trimmedSummary,
                             notes: notes)
    }

    /// Touch ID inside this window rather than the system prompt, which is
    /// another process's window and pulls focus away from ours. Without a
    /// usable fingerprint sensor, fall back to the prompt (it offers the password).
    private func startCopy() {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else {
            state.copyToClipboard(token)
            return
        }
        copyContext = context  // shows the glyph, whose .task calls authenticate
    }

    /// Runs once the glyph is on screen: evaluating a context before its
    /// LAAuthenticationView exists makes macOS show the system prompt instead.
    private func authenticate(with context: LAContext) async {
        defer { copyContext = nil }
        do {
            try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "copy the GitHub token “\(token.label)” to the clipboard")
            state.copyToClipboard(token, context: context)
        } catch let error as LAError
                    where [.userCancel, .appCancel, .systemCancel].contains(error.code) {
            // cancelled — stay silent
        } catch {
            // lockout or too many misses: the prompt can take the password
            state.copyToClipboard(token)
        }
    }
}
