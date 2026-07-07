import AppKit
import Foundation
import GitHubTouchCore
import LocalAuthentication

@MainActor
final class AppState: ObservableObject {
    @Published var vault: VaultFile?
    @Published var activation = ActivationState()
    @Published var lastError: String?
    @Published var vaultCorrupt = false
    @Published var ghLoggedIn = false

    let gh = GhBridge.discover()
    let store: VaultStore
    let stateStore: ActivationStateStore
    private var clearTimer: Timer?

    init(store: VaultStore = VaultStore(), stateStore: ActivationStateStore = ActivationStateStore()) {
        self.store = store
        self.stateStore = stateStore
        do {
            vault = try store.load()
        } catch {
            vaultCorrupt = true
        }
        activation = stateStore.load()
        checkDeadline()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.checkDeadline() }
        }
        refreshGhLoginState()
    }

    func refreshGhLoginState() {
        guard let gh else { return }
        Task {
            let loggedIn = await Task.detached { gh.isLoggedIn() }.value
            self.ghLoggedIn = loggedIn
        }
    }

    var tokens: [TokenEntry] { vault?.tokens ?? [] }
    var activeToken: TokenEntry? { tokens.first { $0.id == activation.activeTokenId } }

    // MARK: - Activate / deactivate / clear

    func activate(_ entry: TokenEntry) {
        guard let vault, let gh else { return }
        Task {
            do {
                // Touch ID fires inside the SE key agreement, off the main actor.
                let token = try await Task.detached {
                    let key = try SecureEnclaveVaultKey.load(
                        blob: vault.seKey,
                        reason: "activate the GitHub token “\(entry.label)”")
                    return try VaultCrypto.unseal(
                        ciphertext: entry.ciphertext, ephemeralPub: entry.ephemeralPub, using: key)
                }.value
                try await Task.detached { try gh.activate(token: token) }.value
                let clearAt = nextMidnight()
                activation = ActivationState(activeTokenId: entry.id, clearAt: clearAt)
                stateStore.save(activation)
                markActivated(entry.id)
                scheduleClear(at: clearAt)
                ghLoggedIn = true
                Notifier.post("“\(entry.label)” active until midnight.")
            } catch let error as LAError where error.code == .userCancel || error.code == .appCancel {
                // user changed their mind — stay silent
            } catch {
                lastError = "\(error)"
                Notifier.post("Activation failed: \(error.localizedDescription)")
            }
        }
    }

    func deactivate(silent: Bool = false) {
        guard let gh else {
            // gh vanished since activation: still drop local state so the
            // icon reflects reality; there is no gh login left to clear.
            activation = ActivationState()
            stateStore.save(activation)
            clearTimer?.invalidate()
            return
        }
        Task {
            do {
                try await Task.detached { try gh.deactivate() }.value
                activation = ActivationState()
                stateStore.save(activation)
                clearTimer?.invalidate()
                ghLoggedIn = false
                if !silent { Notifier.post("GitHub token cleared.") }
            } catch {
                lastError = "\(error)"
                Notifier.post("Could not clear the token: \(error.localizedDescription)")
                if activation.isOverdue() {
                    scheduleClear(at: Date(timeIntervalSinceNow: 60))  // keep retrying an overdue clear
                }
            }
        }
    }

    /// Called at launch, on wake, and by the midnight timer.
    func checkDeadline() {
        if activation.isOverdue() {
            deactivate()
        } else if let clearAt = activation.clearAt {
            scheduleClear(at: clearAt)
        }
    }

    func scheduleClear(at date: Date) {
        clearTimer?.invalidate()
        let timer = Timer(fire: date, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.checkDeadline() }
        }
        RunLoop.main.add(timer, forMode: .common)
        clearTimer = timer
    }

    // MARK: - Vault mutations

    func addToken(label: String, kind: TokenKind, permissions: [String], summary: String?,
                  expiresAt: Date?, notes: String, secret: String) throws {
        var v = try ensureVault()
        let sealed = try VaultCrypto.seal(secret, recipientPub: v.sePub)
        v.tokens.append(TokenEntry(
            id: UUID(), label: label, kind: kind, permissions: permissions,
            expiresAt: expiresAt, createdAt: Date(), lastActivatedAt: nil, notes: notes,
            summary: summary,
            ephemeralPub: sealed.ephemeralPub, ciphertext: sealed.ciphertext))
        try store.save(v)
        vault = v
    }

    func updateMetadata(id: UUID, label: String, permissions: [String], summary: String?, notes: String) {
        guard var v = vault, let index = v.tokens.firstIndex(where: { $0.id == id }) else { return }
        v.tokens[index].label = label
        v.tokens[index].permissions = permissions
        v.tokens[index].summary = summary
        v.tokens[index].notes = notes
        do {
            try store.save(v)
        } catch {
            Notifier.post("Could not save the vault: \(error.localizedDescription)")
        }
        vault = v
    }

    func deleteToken(id: UUID) {
        guard var v = vault else { return }
        v.tokens.removeAll { $0.id == id }
        do {
            try store.save(v)
        } catch {
            Notifier.post("Could not save the vault: \(error.localizedDescription)")
        }
        vault = v
    }

    func resetVault() {
        try? FileManager.default.removeItem(at: store.vaultURL)
        vault = nil
        vaultCorrupt = false
        activation = ActivationState()
        stateStore.save(activation)
        clearTimer?.invalidate()
    }

    private func markActivated(_ id: UUID) {
        guard var v = vault, let index = v.tokens.firstIndex(where: { $0.id == id }) else { return }
        v.tokens[index].lastActivatedAt = Date()
        do {
            try store.save(v)
        } catch {
            Notifier.post("Could not save the vault: \(error.localizedDescription)")
        }
        vault = v
    }

    private func ensureVault() throws -> VaultFile {
        if let vault { return vault }
        let key = try SecureEnclaveVaultKey.create()
        let v = VaultFile(version: 1, seKey: key.dataRepresentation,
                          sePub: key.publicKey.x963Representation, tokens: [])
        try store.save(v)
        vault = v
        return v
    }
}

extension AppState {
    /// Offer the migration while the vault has no tokens but gh is still logged in.
    var canImportExistingToken: Bool {
        tokens.isEmpty && ghLoggedIn
    }

    enum ImportError: LocalizedError {
        case noToken
        case logoutFailed

        var errorDescription: String? {
            switch self {
            case .noToken:
                return "gh reported no current token."
            case .logoutFailed:
                return "Token imported to the vault, but logging gh out failed — run `gh auth logout` in a terminal."
            }
        }
    }

    func importCurrentToken() async throws -> String {
        guard let gh, let token = await Task.detached(operation: { gh.currentToken() }).value else {
            throw ImportError.noToken
        }
        let info = try await TokenValidator().validate(token)
        let label = "full access (legacy OAuth)"
        let generated = DescriptionBuilder.build(kind: .oauth, scopes: info.scopes,
                                                 probe: nil, expiresAt: info.expiresAt)
        try addToken(label: label, kind: .oauth,
                     permissions: generated.details.isEmpty ? (info.scopes ?? []) : generated.details,
                     summary: generated.summary.isEmpty ? nil : generated.summary,
                     expiresAt: info.expiresAt,
                     notes: "imported from gh keychain on \(Date().formatted(date: .abbreviated, time: .omitted))",
                     secret: token)
        do {
            try await Task.detached { try gh.deactivate() }.value
        } catch {
            throw ImportError.logoutFailed
        }
        activation = ActivationState()
        stateStore.save(activation)
        ghLoggedIn = false
        return label
    }
}
