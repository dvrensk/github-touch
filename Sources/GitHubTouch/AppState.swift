import AppKit
import Foundation
import GitHubTouchCore
import LocalAuthentication

@MainActor
final class AppState: ObservableObject {
    @Published var vault: VaultFile?
    @Published var activation = ActivationState() {
        didSet { now = Date() }  // keep the countdown honest right after a change
    }
    @Published var lastError: String?
    @Published var vaultCorrupt = false
    @Published var ghLoggedIn = false
    @Published var duration: ActivationDuration {
        didSet { stateStore.saveDuration(duration) }
    }
    /// Ticks every 30 s so countdowns in the menu and menu bar stay current.
    @Published var now = Date()

    let gh = GhBridge.discover()
    let store: VaultStore
    let stateStore: ActivationStateStore
    private var clearTimer: Timer?
    private var tickTimer: Timer?
    private var handlingDeadline = false

    /// The default token's secret, unsealed with the same touch as a timed
    /// token so switching back at the deadline needs no prompt. Memory only.
    private struct HeldDefault {
        let id: UUID
        let secret: String
    }
    private var heldDefault: HeldDefault?

    init(store: VaultStore = VaultStore(), stateStore: ActivationStateStore = ActivationStateStore()) {
        self.store = store
        self.stateStore = stateStore
        duration = stateStore.loadDuration()
        do {
            vault = try store.load()
        } catch {
            vaultCorrupt = true
        }
        activation = stateStore.load().reconciled(withDefault: vault?.defaultTokenId)
        stateStore.save(activation)
        checkDeadline()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.checkDeadline() }
        }
        let tick = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.now = Date() }
        }
        RunLoop.main.add(tick, forMode: .common)
        tickTimer = tick
        refreshGhLoginState()
        Notifier.bootstrap()
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
    var defaultTokenId: UUID? { vault?.defaultTokenId }
    var defaultToken: TokenEntry? { tokens.first { $0.id == defaultTokenId } }

    var canSwitchToDefault: Bool {
        heldDefault != nil && activation.isActive && activation.activeTokenId != defaultTokenId
    }

    // MARK: - Activate / deactivate / clear

    func activate(_ entry: TokenEntry) {
        guard let vault, let gh else { return }
        let isDefault = entry.id == vault.defaultTokenId
        let defaultToUnseal = isDefault ? nil : defaultToken.flatMap { d in
            !d.isExpired() && heldDefault?.id != d.id ? d : nil
        }
        let duration = self.duration
        Task {
            do {
                // Touch ID fires inside the SE key agreement, off the main actor.
                let (token, defaultSecret) = try await Task.detached {
                    let key = try SecureEnclaveVaultKey.load(
                        blob: vault.seKey,
                        reason: "activate the GitHub token “\(entry.label)”")
                    let token = try VaultCrypto.unseal(
                        ciphertext: entry.ciphertext, ephemeralPub: entry.ephemeralPub, using: key)
                    // Same loaded key, same touch: unseal the default too.
                    let defaultSecret = defaultToUnseal.flatMap { d in
                        try? VaultCrypto.unseal(
                            ciphertext: d.ciphertext, ephemeralPub: d.ephemeralPub, using: key)
                    }
                    return (token, defaultSecret)
                }.value
                try await Task.detached { try gh.activate(token: token) }.value
                if isDefault {
                    activation = ActivationState(activeTokenId: entry.id)
                    heldDefault = nil
                    clearTimer?.invalidate()
                    Notifier.post("“\(entry.label)” active (default).")
                } else {
                    let clearAt = duration.clearAt(from: Date())
                    activation = ActivationState(activeTokenId: entry.id, clearAt: clearAt,
                                                 untilMidnight: duration == .untilMidnight)
                    if let defaultSecret, let d = defaultToUnseal {
                        heldDefault = HeldDefault(id: d.id, secret: defaultSecret)
                    }
                    scheduleClear(at: clearAt)
                    let until = duration == .untilMidnight
                        ? "midnight" : clearAt.formatted(date: .omitted, time: .shortened)
                    Notifier.post("“\(entry.label)” active until \(until).")
                }
                stateStore.save(activation)
                markActivated(entry.id)
                ghLoggedIn = true
            } catch let error as LAError where error.code == .userCancel || error.code == .appCancel {
                // user changed their mind — stay silent
            } catch {
                lastError = "\(error)"
                Notifier.post("Activation failed: \(error.localizedDescription)")
            }
        }
    }

    @discardableResult
    func deactivate(silent: Bool = false, message: String = "GitHub token cleared.") -> Task<Void, Never>? {
        guard let gh else {
            // gh vanished since activation: still drop local state so the
            // icon reflects reality; there is no gh login left to clear.
            activation = ActivationState()
            stateStore.save(activation)
            clearTimer?.invalidate()
            heldDefault = nil
            return nil
        }
        return Task {
            do {
                try await Task.detached { try gh.deactivate() }.value
                activation = ActivationState()
                stateStore.save(activation)
                clearTimer?.invalidate()
                heldDefault = nil
                ghLoggedIn = false
                if !silent { Notifier.post(message) }
            } catch {
                lastError = "\(error)"
                Notifier.post("Could not clear the token: \(error.localizedDescription)")
                if activation.isOverdue() {
                    scheduleClear(at: Date(timeIntervalSinceNow: 60))  // keep retrying an overdue clear
                }
            }
        }
    }

    /// Called at launch, on wake, and by the clear timer.
    func checkDeadline() {
        if activation.isOverdue() {
            handleDeadline()
        } else if let clearAt = activation.clearAt {
            scheduleClear(at: clearAt)
        }
    }

    /// Wake and the timer can both fire for the same deadline; run it once.
    private func handleDeadline() {
        guard !handlingDeadline else { return }
        handlingDeadline = true
        let expiring = activeToken?.label ?? "GitHub token"
        let action = deadlineAction(defaultTokenId: defaultTokenId, heldDefaultId: heldDefault?.id,
                                    defaultExpired: defaultToken?.isExpired() ?? false)
        Task {
            switch action {
            case .switchToDefault:
                await switchToHeldDefault()
            case .logout(.noDefault):
                await deactivate()?.value
            case .logout(.defaultNotHeld), .logout(.defaultChanged):
                await deactivate(message: "“\(expiring)” cleared. Pick the default in the menu to restore it.")?.value
            case .logout(.defaultExpired):
                let label = defaultToken?.label ?? "token"
                await deactivate(message: "“\(expiring)” cleared. The default “\(label)” has expired.")?.value
            }
            handlingDeadline = false
        }
    }

    func switchToDefaultNow() {
        Task { await switchToHeldDefault() }
    }

    private func switchToHeldDefault() async {
        guard let gh, let held = heldDefault,
              let label = tokens.first(where: { $0.id == held.id })?.label else {
            // The default went away between deciding and acting; a deadline
            // must still end the hot token.
            if activation.isOverdue() { await deactivate()?.value }
            return
        }
        let secret = held.secret
        do {
            try await Task.detached { try gh.activate(token: secret) }.value
            activation = ActivationState(activeTokenId: held.id)
            stateStore.save(activation)
            clearTimer?.invalidate()
            heldDefault = nil
            markActivated(held.id)
            ghLoggedIn = true
            Notifier.post("Back to “\(label)” (default).")
        } catch {
            lastError = "\(error)"
            await deactivate(message: "Could not switch back to “\(label)”, so the GitHub token was cleared.")?.value
        }
    }

    func extend() {
        activation = activation.extended(by: duration)
        stateStore.save(activation)
        if let clearAt = activation.clearAt { scheduleClear(at: clearAt) }
    }

    func scheduleClear(at date: Date) {
        clearTimer?.invalidate()
        let timer = Timer(fire: date, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.checkDeadline() }
        }
        RunLoop.main.add(timer, forMode: .common)
        clearTimer = timer
    }

    // MARK: - Export

    /// Clipboard managers that honour nspasteboard.org skip items carrying this type.
    private static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    private static let clipboardLifetime: Duration = .seconds(60)

    /// Unseals a token (Touch ID) onto the clipboard, then wipes it after a
    /// minute unless something else has been copied since.
    func copyToClipboard(_ entry: TokenEntry) {
        guard let vault else { return }
        Task {
            do {
                let token = try await Task.detached {
                    let key = try SecureEnclaveVaultKey.load(
                        blob: vault.seKey,
                        reason: "copy the GitHub token “\(entry.label)” to the clipboard")
                    return try VaultCrypto.unseal(
                        ciphertext: entry.ciphertext, ephemeralPub: entry.ephemeralPub, using: key)
                }.value
                let pasteboard = NSPasteboard.general
                pasteboard.declareTypes([.string, Self.concealedType], owner: nil)
                pasteboard.setString(token, forType: .string)
                pasteboard.setData(Data(), forType: Self.concealedType)
                let changeCount = pasteboard.changeCount
                Notifier.post("“\(entry.label)” copied. The clipboard clears in 1 minute.")
                try? await Task.sleep(for: Self.clipboardLifetime)
                if pasteboard.changeCount == changeCount { pasteboard.clearContents() }
            } catch let error as LAError where error.code == .userCancel || error.code == .appCancel {
                // user changed their mind — stay silent
            } catch {
                lastError = "\(error)"
                Notifier.post("Copy failed: \(error.localizedDescription)")
            }
        }
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
        persist(v)
    }

    func setTag(id: UUID, tag: TokenTag?) {
        guard var v = vault, let index = v.tokens.firstIndex(where: { $0.id == id }) else { return }
        v.tokens[index].tag = tag
        persist(v)
    }

    func setDefault(id: UUID?) {
        guard var v = vault else { return }
        v.defaultTokenId = id
        persist(v)
        if heldDefault?.id != id { heldDefault = nil }
        activation = activation.reconciled(withDefault: id)
        stateStore.save(activation)
        if let clearAt = activation.clearAt {
            scheduleClear(at: clearAt)
        } else {
            clearTimer?.invalidate()
        }
    }

    func deleteToken(id: UUID) {
        guard var v = vault else { return }
        v.tokens.removeAll { $0.id == id }
        if v.defaultTokenId == id { v.defaultTokenId = nil }
        if heldDefault?.id == id { heldDefault = nil }
        persist(v)
        // A deleted token can't be named, timed or restored: don't leave it live.
        if activation.activeTokenId == id { deactivate() }
    }

    func resetVault() {
        try? FileManager.default.removeItem(at: store.vaultURL)
        vault = nil
        vaultCorrupt = false
        activation = ActivationState()
        stateStore.save(activation)
        clearTimer?.invalidate()
        heldDefault = nil
    }

    private func markActivated(_ id: UUID) {
        guard var v = vault, let index = v.tokens.firstIndex(where: { $0.id == id }) else { return }
        v.tokens[index].lastActivatedAt = Date()
        persist(v)
    }

    private func persist(_ v: VaultFile) {
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
