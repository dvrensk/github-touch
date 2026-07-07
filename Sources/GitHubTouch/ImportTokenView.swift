import GitHubTouchCore
import SwiftUI

struct ImportTokenView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var working = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import your current gh token").font(.headline)
            Text("gh is currently logged in with a token stored in the keychain. "
                 + "GitHub Touch can move it into the Touch ID vault as "
                 + "“full access (legacy OAuth)” and then log gh out, so no token "
                 + "remains active. You can re-activate it any time with your fingerprint.")
                .fixedSize(horizontal: false, vertical: true)
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Not Now") { dismiss() }
                Button(working ? "Importing…" : "Import & Log gh Out") { runImport() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(working)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func runImport() {
        working = true
        Task { @MainActor in
            defer { working = false }
            do {
                let label = try await state.importCurrentToken()
                Notifier.post("Imported “\(label)” into the vault and logged gh out.")
                dismiss()
            } catch {
                errorMessage = "Import failed: \(error.localizedDescription)"
            }
        }
    }
}
