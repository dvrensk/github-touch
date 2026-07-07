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
        guard let gh else { return }
        Task {
            do {
                try await Task.detached { try gh.deactivate() }.value
                activation = ActivationState()
                stateStore.save(activation)
                clearTimer?.invalidate()
                if !silent { Notifier.post("GitHub token cleared.") }
            } catch {
                lastError = "\(error)"
                Notifier.post("Could not clear the token: \(error.localizedDescription)")
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

    func addToken(label: String, kind: TokenKind, permissions: [String],
                  expiresAt: Date?, notes: String, secret: String) throws {
        var v = try ensureVault()
        let sealed = try VaultCrypto.seal(secret, recipientPub: v.sePub)
        v.tokens.append(TokenEntry(
            id: UUID(), label: label, kind: kind, permissions: permissions,
            expiresAt: expiresAt, createdAt: Date(), lastActivatedAt: nil, notes: notes,
            ephemeralPub: sealed.ephemeralPub, ciphertext: sealed.ciphertext))
        try store.save(v)
        vault = v
    }

    func updateMetadata(id: UUID, label: String, permissions: [String], notes: String) {
        guard var v = vault, let index = v.tokens.firstIndex(where: { $0.id == id }) else { return }
        v.tokens[index].label = label
        v.tokens[index].permissions = permissions
        v.tokens[index].notes = notes
        try? store.save(v)
        vault = v
    }

    func deleteToken(id: UUID) {
        guard var v = vault else { return }
        v.tokens.removeAll { $0.id == id }
        try? store.save(v)
        vault = v
    }

    func resetVault() {
        try? FileManager.default.removeItem(at: store.vaultURL)
        vault = nil
        vaultCorrupt = false
    }

    private func markActivated(_ id: UUID) {
        guard var v = vault, let index = v.tokens.firstIndex(where: { $0.id == id }) else { return }
        v.tokens[index].lastActivatedAt = Date()
        try? store.save(v)
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
