import AppKit
import GitHubTouchCore
import SwiftUI

struct AddTokenView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var kind: TokenKind = .fineGrained
    @State private var label = ""
    @State private var selectedScopes: Set<String> = []
    @State private var pastedToken = ""
    @State private var permissionsText = ""
    @State private var notes = ""
    @State private var validatedInfo: TokenInfo?
    @State private var validating = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("1 · Describe the token") {
                Picker("Kind", selection: $kind) {
                    Text("Fine-grained (recommended)").tag(TokenKind.fineGrained)
                    Text("Classic").tag(TokenKind.classic)
                }
                .pickerStyle(.radioGroup)
                TextField("Label", text: $label, prompt: Text("e.g. repo read-only"))
                if kind == .classic {
                    ForEach(TokenURLBuilder.classicScopeChoices, id: \.scope) { choice in
                        Toggle("\(choice.scope) — \(choice.help)", isOn: scopeBinding(choice.scope))
                    }
                }
            }
            Section("2 · Generate it on github.com") {
                if kind == .fineGrained {
                    Text("On the GitHub page: set a name and expiry, pick the repositories, "
                         + "and select only the permissions you need. GitHub ignores URL "
                         + "prefills for fine-grained tokens.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Button("Open GitHub…") { openGitHub() }
            }
            Section("3 · Paste and validate") {
                SecureField("Paste the new token", text: $pastedToken)
                Button(validating ? "Validating…" : "Validate") { validate() }
                    .disabled(pastedToken.isEmpty || validating)
                if let info = validatedInfo {
                    Text("Valid for @\(info.login)"
                         + (info.expiresAt.map { ", expires \($0.formatted(date: .abbreviated, time: .omitted))" } ?? ""))
                        .foregroundStyle(.green)
                    TextField("Permissions (comma-separated)", text: $permissionsText)
                    TextField("Notes", text: $notes)
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save to Vault") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(validatedInfo == nil || label.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func scopeBinding(_ scope: String) -> Binding<Bool> {
        Binding(
            get: { selectedScopes.contains(scope) },
            set: { on in if on { selectedScopes.insert(scope) } else { selectedScopes.remove(scope) } })
    }

    private func openGitHub() {
        let url = kind == .classic
            ? TokenURLBuilder.classicNewTokenURL(scopes: selectedScopes.sorted(), description: label)
            : TokenURLBuilder.fineGrainedNewTokenURL
        NSWorkspace.shared.open(url)
    }

    private func validate() {
        validating = true
        errorMessage = nil
        let token = pastedToken
        Task { @MainActor in
            defer { validating = false }
            do {
                let info = try await TokenValidator().validate(token)
                validatedInfo = info
                if let scopes = info.scopes {
                    permissionsText = scopes.joined(separator: ", ")
                }
            } catch TokenValidationError.invalidToken {
                errorMessage = "GitHub rejected that token (401). Check the paste and try again."
            } catch {
                errorMessage = "Validation failed: \(error.localizedDescription)"
            }
        }
    }

    private func save() {
        guard let info = validatedInfo else { return }
        let permissions = permissionsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        do {
            try state.addToken(label: label, kind: kind, permissions: permissions,
                               expiresAt: info.expiresAt, notes: notes, secret: pastedToken)
            pastedToken = ""
            dismiss()
        } catch {
            errorMessage = "Could not save: \(error.localizedDescription)"
        }
    }
}
