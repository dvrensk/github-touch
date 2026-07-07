# GitHub Touch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A macOS menu bar app that stores multiple GitHub tokens encrypted under a Touch ID-gated Secure Enclave key, activates a chosen token into `gh`'s keychain via `gh auth login --with-token`, and clears it at midnight.

**Architecture:** SPM package with a testable core library (`GitHubTouchCore`: vault crypto, vault file store, gh CLI bridge, token validation, activation state) and a SwiftUI `MenuBarExtra` executable (`GitHubTouch`) that composes them. `build.sh` wraps the release binary into `GitHub Touch.app` (ad-hoc signed, installed to `~/Applications`), mirroring the sibling project `../ssh-touch-add`.

**Tech Stack:** Swift 5.10 language mode (Swift 6.2 toolchain), SwiftUI `MenuBarExtra`, CryptoKit (Secure Enclave P-256 + AES-GCM + HKDF), LocalAuthentication, ServiceManagement (`SMAppService`), XCTest via `swift test`.

**Spec:** `docs/superpowers/specs/2026-07-07-github-touch-design.md`

## Global Constraints

- Platform floor: macOS 13.0 (`platforms: [.macOS(.v13)]`, `LSMinimumSystemVersion` 13.0). Dev machine runs macOS 15 / Apple Silicon.
- No third-party dependencies. Apple frameworks only.
- No user-facing CLI. Debug-only flags on the binary (`--test-plumbing`) are allowed.
- App name: `GitHub Touch`. Bundle id: `se.vrensk.github-touch`. Executable name: `GitHubTouch`.
- Vault file: `~/Library/Application Support/github-touch/vault.json`, mode 600, written atomically.
- HKDF `sharedInfo` string: exactly `"github-touch v1"`.
- GitHub host is always `github.com` (single account, user `dvrensk`).
- A plaintext token must never appear on a command line (argv), in a file, or in the pasteboard — stdin pipe to `gh` only.
- Child processes must run with `GH_TOKEN` and `GITHUB_TOKEN` removed from the environment.
- UserDefaults keys for activation state: `activeTokenId` (UUID string), `clearAt` (Date).
- Commit after every task (at minimum); use the `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>` trailer.

---

### Task 1: SPM scaffold, app shell, build.sh

**Files:**
- Create: `Package.swift`
- Create: `Sources/GitHubTouchCore/Placeholder.swift` (removed in Task 2)
- Create: `Sources/GitHubTouch/Main.swift`
- Create: `Sources/GitHubTouch/GitHubTouchApp.swift`
- Create: `Tests/GitHubTouchCoreTests/SmokeTests.swift` (removed in Task 2)
- Create: `build.sh`
- Create: `.gitignore`

**Interfaces:**
- Consumes: nothing.
- Produces: the package layout every later task drops files into; `build.sh` producing `GitHub Touch.app`; `Main.main()` which later gains the `--test-plumbing` branch (Task 12).

- [ ] **Step 1: Write Package.swift and .gitignore**

`Package.swift`:

```swift
// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "GitHubTouch",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "GitHubTouchCore"),
        .executableTarget(name: "GitHubTouch", dependencies: ["GitHubTouchCore"]),
        .testTarget(name: "GitHubTouchCoreTests", dependencies: ["GitHubTouchCore"]),
    ]
)
```

`.gitignore`:

```
.build/
.DS_Store
GitHub Touch.app/
```

- [ ] **Step 2: Write the minimal app shell**

`Sources/GitHubTouchCore/Placeholder.swift`:

```swift
// Temporary: gives the core target a compilable member until Task 2.
public enum CorePlaceholder {}
```

`Sources/GitHubTouch/GitHubTouchApp.swift`:

```swift
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
```

`Sources/GitHubTouch/Main.swift`:

```swift
// Custom entry point so debug flags (Task 12) can run without starting the UI.
@main
enum Main {
    static func main() {
        GitHubTouchApp.main()
    }
}
```

`Tests/GitHubTouchCoreTests/SmokeTests.swift`:

```swift
import XCTest

final class SmokeTests: XCTestCase {
    func testTestTargetRuns() { XCTAssertTrue(true) }
}
```

- [ ] **Step 3: Verify build and tests**

Run: `swift build && swift test`
Expected: `Build complete!` and `Executed 1 test, with 0 failures`.

- [ ] **Step 4: Write build.sh**

```bash
#!/bin/bash
# Rebuild GitHub Touch and refresh the app bundle in ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN=.build/release/GitHubTouch

APP="GitHub Touch.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/GitHubTouch"
if [ -f icons/AppIcon.icns ]; then
  cp icons/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi
if ls icons/MenuIconTemplate*.png >/dev/null 2>&1; then
  cp icons/MenuIconTemplate*.png "$APP/Contents/Resources/"
fi
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key><string>GitHub Touch</string>
	<key>CFBundleDisplayName</key><string>GitHub Touch</string>
	<key>CFBundleIdentifier</key><string>se.vrensk.github-touch</string>
	<key>CFBundleVersion</key><string>1.0</string>
	<key>CFBundleShortVersionString</key><string>1.0</string>
	<key>CFBundleExecutable</key><string>GitHubTouch</string>
	<key>CFBundleIconFile</key><string>AppIcon</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>LSMinimumSystemVersion</key><string>13.0</string>
	<key>LSUIElement</key><true/>
	<key>NSHumanReadableCopyright</key><string>Local tool</string>
</dict>
</plist>
EOF
codesign -s - --force --deep "$APP"

rm -rf ~/Applications/"$APP"
cp -R "$APP" ~/Applications/
echo "Built, signed, and installed to ~/Applications/$APP"
```

Then: `chmod +x build.sh`

- [ ] **Step 5: Verify the bundle launches**

Run: `./build.sh && open ~/Applications/"GitHub Touch.app"`
Expected: a fingerprint icon appears in the menu bar with a "Quit" item. Quit it from the menu.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources Tests build.sh .gitignore
git commit -m "feat: SPM scaffold, menu bar shell, app bundle build script"
```

---

### Task 2: Token models + vault crypto

**Files:**
- Create: `Sources/GitHubTouchCore/TokenModels.swift`
- Create: `Sources/GitHubTouchCore/VaultCrypto.swift`
- Delete: `Sources/GitHubTouchCore/Placeholder.swift`, `Tests/GitHubTouchCoreTests/SmokeTests.swift`
- Test: `Tests/GitHubTouchCoreTests/VaultCryptoTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `TokenKind: String, Codable, CaseIterable` — cases `.fineGrained`, `.classic`, `.oauth`; `var displayName: String`.
  - `TokenEntry: Codable, Identifiable, Equatable` — fields `id: UUID`, `label: String`, `kind: TokenKind`, `permissions: [String]`, `expiresAt: Date?`, `createdAt: Date`, `lastActivatedAt: Date?`, `notes: String`, `ephemeralPub: Data`, `ciphertext: Data`; method `isExpired(now: Date = Date()) -> Bool`.
  - `VaultFile: Codable` — `version: Int`, `seKey: Data`, `sePub: Data`, `tokens: [TokenEntry]`.
  - `protocol AgreementPrivateKey` — `var x963PublicKey: Data`, `func sharedSecret(withEphemeralPub: Data) throws -> SharedSecret`; conformances for `P256.KeyAgreement.PrivateKey` and `SecureEnclave.P256.KeyAgreement.PrivateKey`.
  - `VaultCrypto.seal(_ secret: String, recipientPub: Data) throws -> (ephemeralPub: Data, ciphertext: Data)`.
  - `VaultCrypto.unseal(ciphertext: Data, ephemeralPub: Data, using: AgreementPrivateKey) throws -> String`.
  - `SecureEnclaveVaultKey.create(requireUserPresence: Bool = true) throws -> SecureEnclave.P256.KeyAgreement.PrivateKey`.
  - `SecureEnclaveVaultKey.load(blob: Data, reason: String) throws -> SecureEnclave.P256.KeyAgreement.PrivateKey`.
  - `VaultError: Error` — case `corruptCiphertext`.

- [ ] **Step 1: Write the failing tests**

`Tests/GitHubTouchCoreTests/VaultCryptoTests.swift` (tests use a *software* P256 key so they run without Touch ID or a Secure Enclave; the SE conformance is exercised by `--test-plumbing` in Task 12):

```swift
import CryptoKit
import XCTest
@testable import GitHubTouchCore

final class VaultCryptoTests: XCTestCase {
    func testSealUnsealRoundTrip() throws {
        let key = P256.KeyAgreement.PrivateKey()
        let (eph, ct) = try VaultCrypto.seal("ghp_secret123", recipientPub: key.x963PublicKey)
        let out = try VaultCrypto.unseal(ciphertext: ct, ephemeralPub: eph, using: key)
        XCTAssertEqual(out, "ghp_secret123")
    }

    func testTokensAreSealedIndependently() throws {
        let key = P256.KeyAgreement.PrivateKey()
        let a = try VaultCrypto.seal("token-a", recipientPub: key.x963PublicKey)
        let b = try VaultCrypto.seal("token-b", recipientPub: key.x963PublicKey)
        XCTAssertNotEqual(a.ephemeralPub, b.ephemeralPub)
        XCTAssertEqual(try VaultCrypto.unseal(ciphertext: a.ciphertext, ephemeralPub: a.ephemeralPub, using: key), "token-a")
        XCTAssertEqual(try VaultCrypto.unseal(ciphertext: b.ciphertext, ephemeralPub: b.ephemeralPub, using: key), "token-b")
    }

    func testUnsealWithWrongKeyThrows() throws {
        let key = P256.KeyAgreement.PrivateKey()
        let other = P256.KeyAgreement.PrivateKey()
        let (eph, ct) = try VaultCrypto.seal("secret", recipientPub: key.x963PublicKey)
        XCTAssertThrowsError(try VaultCrypto.unseal(ciphertext: ct, ephemeralPub: eph, using: other))
    }

    func testVaultFileCodableRoundTrip() throws {
        let entry = TokenEntry(
            id: UUID(), label: "repo read-only", kind: .fineGrained,
            permissions: ["contents: read", "metadata: read"],
            expiresAt: Date(timeIntervalSince1970: 1_790_000_000),
            createdAt: Date(timeIntervalSince1970: 1_780_000_000),
            lastActivatedAt: nil, notes: "for CI tools",
            ephemeralPub: Data([1, 2]), ciphertext: Data([3, 4]))
        let vault = VaultFile(version: 1, seKey: Data([9]), sePub: Data([8]), tokens: [entry])
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let back = try dec.decode(VaultFile.self, from: enc.encode(vault))
        XCTAssertEqual(back.tokens, [entry])
        XCTAssertEqual(back.version, 1)
    }

    func testIsExpired() {
        var entry = TokenEntry(
            id: UUID(), label: "x", kind: .classic, permissions: [],
            expiresAt: nil, createdAt: Date(), lastActivatedAt: nil, notes: "",
            ephemeralPub: Data(), ciphertext: Data())
        XCTAssertFalse(entry.isExpired())
        entry.expiresAt = Date(timeIntervalSinceNow: -60)
        XCTAssertTrue(entry.isExpired())
        entry.expiresAt = Date(timeIntervalSinceNow: 60)
        XCTAssertFalse(entry.isExpired())
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test 2>&1 | tail -5`
Expected: compilation failure — `TokenEntry`, `VaultCrypto` etc. not defined.

- [ ] **Step 3: Implement models and crypto**

Delete `Sources/GitHubTouchCore/Placeholder.swift` and `Tests/GitHubTouchCoreTests/SmokeTests.swift`.

`Sources/GitHubTouchCore/TokenModels.swift`:

```swift
import Foundation

public enum TokenKind: String, Codable, CaseIterable, Sendable {
    case fineGrained, classic, oauth

    public var displayName: String {
        switch self {
        case .fineGrained: return "Fine-grained PAT"
        case .classic: return "Classic PAT"
        case .oauth: return "OAuth token"
        }
    }
}

public struct TokenEntry: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var label: String
    public var kind: TokenKind
    public var permissions: [String]
    public var expiresAt: Date?
    public var createdAt: Date
    public var lastActivatedAt: Date?
    public var notes: String
    public var ephemeralPub: Data
    public var ciphertext: Data

    public init(id: UUID, label: String, kind: TokenKind, permissions: [String],
                expiresAt: Date?, createdAt: Date, lastActivatedAt: Date?, notes: String,
                ephemeralPub: Data, ciphertext: Data) {
        self.id = id
        self.label = label
        self.kind = kind
        self.permissions = permissions
        self.expiresAt = expiresAt
        self.createdAt = createdAt
        self.lastActivatedAt = lastActivatedAt
        self.notes = notes
        self.ephemeralPub = ephemeralPub
        self.ciphertext = ciphertext
    }

    public func isExpired(now: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= now
    }

    public var permissionSummary: String {
        permissions.isEmpty ? "no recorded permissions" : permissions.joined(separator: ", ")
    }
}

public struct VaultFile: Codable, Sendable {
    public var version: Int
    public var seKey: Data   // Secure Enclave private key blob (usable only on this Mac)
    public var sePub: Data   // its x9.63 public key, for sealing without an SE round-trip
    public var tokens: [TokenEntry]

    public init(version: Int, seKey: Data, sePub: Data, tokens: [TokenEntry]) {
        self.version = version
        self.seKey = seKey
        self.sePub = sePub
        self.tokens = tokens
    }
}
```

`Sources/GitHubTouchCore/VaultCrypto.swift`:

```swift
import CryptoKit
import Foundation
import LocalAuthentication

public enum VaultError: Error {
    case corruptCiphertext
}

// Abstracts over the Secure Enclave key (production) and a software P256 key
// (tests, --test-plumbing) so the crypto is unit-testable without Touch ID.
public protocol AgreementPrivateKey {
    var x963PublicKey: Data { get }
    func sharedSecret(withEphemeralPub ephemeralPub: Data) throws -> SharedSecret
}

extension P256.KeyAgreement.PrivateKey: AgreementPrivateKey {
    public var x963PublicKey: Data { publicKey.x963Representation }
    public func sharedSecret(withEphemeralPub ephemeralPub: Data) throws -> SharedSecret {
        try sharedSecretFromKeyAgreement(with: P256.KeyAgreement.PublicKey(x963Representation: ephemeralPub))
    }
}

extension SecureEnclave.P256.KeyAgreement.PrivateKey: AgreementPrivateKey {
    public var x963PublicKey: Data { publicKey.x963Representation }
    public func sharedSecret(withEphemeralPub ephemeralPub: Data) throws -> SharedSecret {
        // Touch ID happens here, inside the SE key agreement.
        try sharedSecretFromKeyAgreement(with: P256.KeyAgreement.PublicKey(x963Representation: ephemeralPub))
    }
}

public enum VaultCrypto {
    static func symmetricKey(_ shared: SharedSecret, ephemeralPub: Data) -> SymmetricKey {
        shared.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: ephemeralPub,
            sharedInfo: Data("github-touch v1".utf8),
            outputByteCount: 32)
    }

    public static func seal(_ secret: String, recipientPub: Data) throws -> (ephemeralPub: Data, ciphertext: Data) {
        let recipient = try P256.KeyAgreement.PublicKey(x963Representation: recipientPub)
        let ephemeral = P256.KeyAgreement.PrivateKey()
        let ephemeralPub = ephemeral.publicKey.x963Representation
        let shared = try ephemeral.sharedSecretFromKeyAgreement(with: recipient)
        let box = try AES.GCM.seal(Data(secret.utf8), using: symmetricKey(shared, ephemeralPub: ephemeralPub))
        return (ephemeralPub, box.combined!)
    }

    public static func unseal(ciphertext: Data, ephemeralPub: Data, using key: AgreementPrivateKey) throws -> String {
        let shared = try key.sharedSecret(withEphemeralPub: ephemeralPub)
        let box = try AES.GCM.SealedBox(combined: ciphertext)
        let plain = try AES.GCM.open(box, using: symmetricKey(shared, ephemeralPub: ephemeralPub))
        guard let secret = String(data: plain, encoding: .utf8) else { throw VaultError.corruptCiphertext }
        return secret
    }
}

public enum SecureEnclaveVaultKey {
    public static func create(requireUserPresence: Bool = true) throws -> SecureEnclave.P256.KeyAgreement.PrivateKey {
        var acError: Unmanaged<CFError>?
        let flags: SecAccessControlCreateFlags = requireUserPresence
            ? [.privateKeyUsage, .userPresence] : [.privateKeyUsage]
        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, flags, &acError) else {
            throw acError!.takeRetainedValue() as Error
        }
        return try SecureEnclave.P256.KeyAgreement.PrivateKey(accessControl: access)
    }

    public static func load(blob: Data, reason: String) throws -> SecureEnclave.P256.KeyAgreement.PrivateKey {
        let context = LAContext()
        context.localizedReason = reason
        return try SecureEnclave.P256.KeyAgreement.PrivateKey(
            dataRepresentation: blob, authenticationContext: context)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test 2>&1 | tail -3`
Expected: `Executed 5 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources Tests
git commit -m "feat: token models and Secure Enclave vault crypto"
```

---

### Task 3: Vault file store

**Files:**
- Create: `Sources/GitHubTouchCore/VaultStore.swift`
- Test: `Tests/GitHubTouchCoreTests/VaultStoreTests.swift`

**Interfaces:**
- Consumes: `VaultFile` (Task 2).
- Produces:
  - `VaultStore` — `init(directory: URL = VaultStore.defaultDirectory)`, `static var defaultDirectory: URL` (`~/Library/Application Support/github-touch`), `var vaultURL: URL`, `func load() throws -> VaultFile?` (nil = no vault yet; throws = corrupt), `func save(_ vault: VaultFile) throws` (atomic, mode 600).

- [ ] **Step 1: Write the failing tests**

`Tests/GitHubTouchCoreTests/VaultStoreTests.swift`:

```swift
import XCTest
@testable import GitHubTouchCore

final class VaultStoreTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault-test-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func makeVault() -> VaultFile {
        VaultFile(version: 1, seKey: Data([1]), sePub: Data([2]), tokens: [])
    }

    func testLoadReturnsNilWhenMissing() throws {
        XCTAssertNil(try VaultStore(directory: dir).load())
    }

    func testSaveThenLoadRoundTrips() throws {
        let store = VaultStore(directory: dir)
        try store.save(makeVault())
        let back = try XCTUnwrap(store.load())
        XCTAssertEqual(back.seKey, Data([1]))
        XCTAssertEqual(back.sePub, Data([2]))
    }

    func testSaveSetsMode600() throws {
        let store = VaultStore(directory: dir)
        try store.save(makeVault())
        let attrs = try FileManager.default.attributesOfItem(atPath: store.vaultURL.path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.int16Value, 0o600)
    }

    func testLoadThrowsOnCorruptFile() throws {
        let store = VaultStore(directory: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.vaultURL)
        XCTAssertThrowsError(try store.load())
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter VaultStoreTests 2>&1 | tail -5`
Expected: compilation failure — `VaultStore` not defined.

- [ ] **Step 3: Implement VaultStore**

`Sources/GitHubTouchCore/VaultStore.swift`:

```swift
import Foundation

public final class VaultStore {
    public let vaultURL: URL

    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("github-touch")
    }

    public init(directory: URL = VaultStore.defaultDirectory) {
        vaultURL = directory.appendingPathComponent("vault.json")
    }

    /// nil means "no vault yet"; a thrown error means the file exists but is unreadable.
    public func load() throws -> VaultFile? {
        guard FileManager.default.fileExists(atPath: vaultURL.path) else { return nil }
        let data = try Data(contentsOf: vaultURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(VaultFile.self, from: data)
    }

    public func save(_ vault: VaultFile) throws {
        try FileManager.default.createDirectory(
            at: vaultURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(vault).write(to: vaultURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: vaultURL.path)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test 2>&1 | tail -3`
Expected: `Executed 9 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources Tests
git commit -m "feat: vault file store with atomic 0600 persistence"
```

---

### Task 4: GhBridge — the gh CLI wrapper

**Files:**
- Create: `Sources/GitHubTouchCore/GhBridge.swift`
- Test: `Tests/GitHubTouchCoreTests/GhBridgeTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  - `GhBridge` — `init(ghPath: String)`, `static func discover(extraPaths: [String] = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"]) -> GhBridge?`, `func isLoggedIn() -> Bool`, `func activate(token: String) throws`, `func deactivate() throws`, `func currentToken() -> String?`.
  - `GhError: Error, Equatable` — cases `loginFailed(String)`, `logoutFailed(String)`.

- [ ] **Step 1: Write the failing tests (against a fake gh script)**

`Tests/GitHubTouchCoreTests/GhBridgeTests.swift`:

```swift
import XCTest
@testable import GitHubTouchCore

final class GhBridgeTests: XCTestCase {
    var dir: URL!
    var ghPath: String { dir.appendingPathComponent("gh").path }
    var bridge: GhBridge { GhBridge(ghPath: ghPath) }

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gh-fake-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Fake gh: `auth login` records stdin and marks logged-in via a state
        // file; `auth status` reports it; `auth logout` clears it.
        let script = """
        #!/bin/bash
        D="$(cd "$(dirname "$0")" && pwd)"
        echo "$*" >> "$D/log"
        case "$1 $2" in
          "auth status") [ -f "$D/state" ] && exit 0 || exit 1 ;;
          "auth login")  cat > "$D/stdin.txt"; touch "$D/state"; exit 0 ;;
          "auth logout") rm -f "$D/state"; exit 0 ;;
          "auth token")  [ -f "$D/state" ] && { echo "gho_fake123"; exit 0; } || exit 1 ;;
        esac
        exit 64
        """
        try script.write(toFile: ghPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ghPath)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testActivateSendsTokenViaStdinNeverArgv() throws {
        try bridge.activate(token: "ghp_supersecret")
        let stdin = try String(contentsOf: dir.appendingPathComponent("stdin.txt"), encoding: .utf8)
        XCTAssertEqual(stdin, "ghp_supersecret")
        let log = try String(contentsOf: dir.appendingPathComponent("log"), encoding: .utf8)
        XCTAssertFalse(log.contains("supersecret"), "token must never appear on argv")
        XCTAssertTrue(log.contains("auth login --hostname github.com --with-token"))
    }

    func testIsLoggedInReflectsGhState() throws {
        XCTAssertFalse(bridge.isLoggedIn())
        try bridge.activate(token: "t")
        XCTAssertTrue(bridge.isLoggedIn())
    }

    func testDeactivateLogsOutAndIsIdempotent() throws {
        try bridge.activate(token: "t")
        try bridge.deactivate()
        XCTAssertFalse(bridge.isLoggedIn())
        try bridge.deactivate() // already logged out: must not throw
    }

    func testCurrentToken() throws {
        XCTAssertNil(bridge.currentToken())
        try bridge.activate(token: "t")
        XCTAssertEqual(bridge.currentToken(), "gho_fake123")
    }

    func testDiscoverReturnsNilWhenAbsent() {
        XCTAssertNil(GhBridge.discover(extraPaths: ["/nonexistent/gh"]))
    }

    func testDiscoverFindsExecutable() {
        XCTAssertEqual(GhBridge.discover(extraPaths: [ghPath])?.ghPath, ghPath)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter GhBridgeTests 2>&1 | tail -5`
Expected: compilation failure — `GhBridge` not defined.

- [ ] **Step 3: Implement GhBridge**

`Sources/GitHubTouchCore/GhBridge.swift`:

```swift
import Foundation

public enum GhError: Error, Equatable {
    case loginFailed(String)
    case logoutFailed(String)
}

public struct GhBridge {
    public let ghPath: String

    public init(ghPath: String) {
        self.ghPath = ghPath
    }

    /// GUI apps get a minimal PATH, so look in the usual Homebrew locations.
    public static func discover(
        extraPaths: [String] = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"]
    ) -> GhBridge? {
        for path in extraPaths where FileManager.default.isExecutableFile(atPath: path) {
            return GhBridge(ghPath: path)
        }
        return nil
    }

    struct ProcessResult {
        var status: Int32
        var stdout: String
        var stderr: String
    }

    func run(_ args: [String], stdin input: String? = nil) -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ghPath)
        process.arguments = args
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "GH_TOKEN")      // must not shadow the keychain
        env.removeValue(forKey: "GITHUB_TOKEN")
        process.environment = env
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        let inPipe: Pipe? = input.map { _ in Pipe() }
        if let inPipe {
            process.standardInput = inPipe
        } else {
            process.standardInput = FileHandle.nullDevice
        }
        do {
            try process.run()
        } catch {
            return ProcessResult(status: 127, stdout: "", stderr: "\(error)")
        }
        if let input, let inPipe {
            inPipe.fileHandleForWriting.write(Data(input.utf8))
            inPipe.fileHandleForWriting.closeFile()
        }
        let stdout = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let stderr = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return ProcessResult(status: process.terminationStatus, stdout: stdout, stderr: stderr)
    }

    public func isLoggedIn() -> Bool {
        run(["auth", "status", "--hostname", "github.com"]).status == 0
    }

    public func activate(token: String) throws {
        let result = run(["auth", "login", "--hostname", "github.com", "--with-token"], stdin: token)
        guard result.status == 0, isLoggedIn() else {
            throw GhError.loginFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    public func deactivate() throws {
        guard isLoggedIn() else { return }
        let result = run(["auth", "logout", "--hostname", "github.com"])
        guard result.status == 0, !isLoggedIn() else {
            throw GhError.logoutFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    public func currentToken() -> String? {
        let result = run(["auth", "token", "--hostname", "github.com"])
        guard result.status == 0 else { return nil }
        let token = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test 2>&1 | tail -3`
Expected: `Executed 15 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources Tests
git commit -m "feat: gh CLI bridge with stdin-only token handoff"
```

---

### Task 5: Token validation against the GitHub API

**Files:**
- Create: `Sources/GitHubTouchCore/TokenValidator.swift`
- Test: `Tests/GitHubTouchCoreTests/TokenValidatorTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  - `TokenInfo: Equatable` — `login: String`, `scopes: [String]?` (nil for fine-grained tokens, which report no scope header), `expiresAt: Date?`.
  - `TokenValidator` — `init(session: URLSession = .shared)`, `func validate(_ token: String) async throws -> TokenInfo`.
  - `TokenValidationError: Error, Equatable` — cases `invalidToken`, `unexpectedStatus(Int)`.

- [ ] **Step 1: Write the failing tests**

`Tests/GitHubTouchCoreTests/TokenValidatorTests.swift`:

```swift
import XCTest
@testable import GitHubTouchCore

final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (response, data) = Self.handler!(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class TokenValidatorTests: XCTestCase {
    var validator: TokenValidator!

    override func setUp() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        validator = TokenValidator(session: URLSession(configuration: config))
    }

    func respond(status: Int, headers: [String: String] = [:], body: String = #"{"login":"dvrensk"}"#) {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.github.com/user")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok123")
            let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                           httpVersion: nil, headerFields: headers)!
            return (response, Data(body.utf8))
        }
    }

    func testClassicTokenScopesAndExpiry() async throws {
        respond(status: 200, headers: [
            "X-OAuth-Scopes": "repo, gist, read:org",
            "GitHub-Authentication-Token-Expiration": "2026-10-01 07:00:00 UTC",
        ])
        let info = try await validator.validate("tok123")
        XCTAssertEqual(info.login, "dvrensk")
        XCTAssertEqual(info.scopes, ["repo", "gist", "read:org"])
        let expected = ISO8601DateFormatter().date(from: "2026-10-01T07:00:00Z")
        XCTAssertEqual(info.expiresAt, expected)
    }

    func testFineGrainedTokenHasNoScopes() async throws {
        respond(status: 200)
        let info = try await validator.validate("tok123")
        XCTAssertNil(info.scopes)
        XCTAssertNil(info.expiresAt)
    }

    func testEmptyScopesHeaderMeansNoScopes() async throws {
        respond(status: 200, headers: ["X-OAuth-Scopes": ""])
        let info = try await validator.validate("tok123")
        XCTAssertNil(info.scopes)
    }

    func testBadTokenThrowsInvalid() async {
        respond(status: 401, body: #"{"message":"Bad credentials"}"#)
        do {
            _ = try await validator.validate("tok123")
            XCTFail("should throw")
        } catch let error as TokenValidationError {
            XCTAssertEqual(error, .invalidToken)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testParseExpirationFormats() {
        XCTAssertNotNil(TokenValidator.parseExpiration("2026-10-01 07:00:00 UTC"))
        XCTAssertNotNil(TokenValidator.parseExpiration("2026-10-01T07:00:00Z"))
        XCTAssertNil(TokenValidator.parseExpiration("never"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter TokenValidatorTests 2>&1 | tail -5`
Expected: compilation failure — `TokenValidator` not defined.

- [ ] **Step 3: Implement TokenValidator**

`Sources/GitHubTouchCore/TokenValidator.swift`:

```swift
import Foundation

public struct TokenInfo: Equatable, Sendable {
    public var login: String
    public var scopes: [String]?   // nil for fine-grained tokens (no scope header)
    public var expiresAt: Date?
}

public enum TokenValidationError: Error, Equatable {
    case invalidToken
    case unexpectedStatus(Int)
}

public struct TokenValidator {
    let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func validate(_ token: String) async throws -> TokenInfo {
        var request = URLRequest(url: URL(string: "https://api.github.com/user")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        let (data, response) = try await session.data(for: request)
        let http = response as! HTTPURLResponse
        guard http.statusCode == 200 else {
            throw http.statusCode == 401
                ? TokenValidationError.invalidToken
                : TokenValidationError.unexpectedStatus(http.statusCode)
        }
        struct User: Decodable { let login: String }
        let user = try JSONDecoder().decode(User.self, from: data)
        let scopes = http.value(forHTTPHeaderField: "X-OAuth-Scopes").map {
            $0.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        let expiry = http.value(forHTTPHeaderField: "GitHub-Authentication-Token-Expiration")
            .flatMap(Self.parseExpiration)
        return TokenInfo(login: user.login,
                         scopes: (scopes?.isEmpty ?? true) ? nil : scopes,
                         expiresAt: expiry)
    }

    /// GitHub sends "2026-10-01 07:00:00 UTC"; be lenient and take ISO8601 too.
    static func parseExpiration(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss zzz"
        if let date = formatter.date(from: string) { return date }
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        if let date = formatter.date(from: string) { return date }
        return ISO8601DateFormatter().date(from: string)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test 2>&1 | tail -3`
Expected: `Executed 21 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources Tests
git commit -m "feat: token validation via GitHub API with scope/expiry detection"
```

---

### Task 6: Activation state + midnight math

**Files:**
- Create: `Sources/GitHubTouchCore/ActivationState.swift`
- Test: `Tests/GitHubTouchCoreTests/ActivationStateTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  - `ActivationState: Equatable` — `activeTokenId: UUID?`, `clearAt: Date?`, `init(activeTokenId: UUID? = nil, clearAt: Date? = nil)`, `var isActive: Bool`, `func isOverdue(now: Date = Date()) -> Bool`.
  - `ActivationStateStore` — `init(defaults: UserDefaults = .standard)`, `func load() -> ActivationState`, `func save(_ state: ActivationState)`.
  - `func nextMidnight(after date: Date = Date(), calendar: Calendar = .current) -> Date`.

- [ ] **Step 1: Write the failing tests**

`Tests/GitHubTouchCoreTests/ActivationStateTests.swift`:

```swift
import XCTest
@testable import GitHubTouchCore

final class ActivationStateTests: XCTestCase {
    func testNextMidnightIsStartOfNextDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
        let formatter = ISO8601DateFormatter()
        let now = formatter.date(from: "2026-07-07T15:30:00+02:00")!
        let midnight = nextMidnight(after: now, calendar: calendar)
        XCTAssertEqual(midnight, formatter.date(from: "2026-07-08T00:00:00+02:00"))
    }

    func testNextMidnightJustBeforeMidnight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
        let formatter = ISO8601DateFormatter()
        let now = formatter.date(from: "2026-07-07T23:59:59+02:00")!
        XCTAssertEqual(nextMidnight(after: now, calendar: calendar),
                       formatter.date(from: "2026-07-08T00:00:00+02:00"))
    }

    func testIsOverdue() {
        let state = ActivationState(activeTokenId: UUID(), clearAt: Date(timeIntervalSinceNow: -1))
        XCTAssertTrue(state.isOverdue())
        let future = ActivationState(activeTokenId: UUID(), clearAt: Date(timeIntervalSinceNow: 60))
        XCTAssertFalse(future.isOverdue())
        XCTAssertFalse(ActivationState().isOverdue())
        XCTAssertFalse(ActivationState().isActive)
    }

    func testStoreRoundTrip() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "github-touch-tests"))
        defaults.removePersistentDomain(forName: "github-touch-tests")
        let store = ActivationStateStore(defaults: defaults)

        XCTAssertEqual(store.load(), ActivationState())

        let state = ActivationState(activeTokenId: UUID(), clearAt: Date(timeIntervalSince1970: 1_790_000_000))
        store.save(state)
        XCTAssertEqual(store.load(), state)

        store.save(ActivationState())
        XCTAssertEqual(store.load(), ActivationState())
        defaults.removePersistentDomain(forName: "github-touch-tests")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ActivationStateTests 2>&1 | tail -5`
Expected: compilation failure — `ActivationState` not defined.

- [ ] **Step 3: Implement ActivationState**

`Sources/GitHubTouchCore/ActivationState.swift`:

```swift
import Foundation

public struct ActivationState: Equatable, Sendable {
    public var activeTokenId: UUID?
    public var clearAt: Date?

    public init(activeTokenId: UUID? = nil, clearAt: Date? = nil) {
        self.activeTokenId = activeTokenId
        self.clearAt = clearAt
    }

    public var isActive: Bool { activeTokenId != nil }

    public func isOverdue(now: Date = Date()) -> Bool {
        guard let clearAt else { return false }
        return now >= clearAt
    }
}

public func nextMidnight(after date: Date = Date(), calendar: Calendar = .current) -> Date {
    calendar.nextDate(after: date,
                      matching: DateComponents(hour: 0, minute: 0, second: 0),
                      matchingPolicy: .nextTime)!
}

public final class ActivationStateStore {
    let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> ActivationState {
        ActivationState(
            activeTokenId: defaults.string(forKey: "activeTokenId").flatMap(UUID.init(uuidString:)),
            clearAt: defaults.object(forKey: "clearAt") as? Date)
    }

    public func save(_ state: ActivationState) {
        if let id = state.activeTokenId {
            defaults.set(id.uuidString, forKey: "activeTokenId")
        } else {
            defaults.removeObject(forKey: "activeTokenId")
        }
        if let clearAt = state.clearAt {
            defaults.set(clearAt, forKey: "clearAt")
        } else {
            defaults.removeObject(forKey: "clearAt")
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test 2>&1 | tail -3`
Expected: `Executed 25 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources Tests
git commit -m "feat: activation state persistence and midnight deadline math"
```

---

### Task 7: AppState + menu bar UI (activate / deactivate / clear scheduling)

**Files:**
- Create: `Sources/GitHubTouch/AppState.swift`
- Create: `Sources/GitHubTouch/MenuContentView.swift`
- Create: `Sources/GitHubTouch/Notifier.swift`
- Modify: `Sources/GitHubTouch/GitHubTouchApp.swift` (replace placeholder body)

**Interfaces:**
- Consumes: everything from Tasks 2–6.
- Produces (used by Tasks 8–10, 12):
  - `AppState: ObservableObject, @MainActor` — `@Published var vault: VaultFile?`, `@Published var activation: ActivationState`, `@Published var lastError: String?`, `let gh: GhBridge?`, `var tokens: [TokenEntry]`, `var activeToken: TokenEntry?`, `func activate(_ entry: TokenEntry)`, `func deactivate(silent: Bool = false)`, `func checkDeadline()`, `func addToken(label:kind:permissions:expiresAt:notes:secret:) throws`, `func updateMetadata(id:label:permissions:notes:)`, `func deleteToken(id: UUID)`, `func scheduleClear(at: Date)`.
  - `Notifier.post(_ message: String, title: String = "GitHub Touch")`.

- [ ] **Step 1: Implement Notifier**

`Sources/GitHubTouch/Notifier.swift` (same strategy as the sibling project: UNUserNotificationCenter when running from the bundle, osascript fallback for bare-binary dev runs):

```swift
import Foundation
import UserNotifications

enum Notifier {
    static func post(_ message: String, title: String = "GitHub Touch") {
        if postBundleNotification(message, title: title) { return }
        let escaped = message.replacingOccurrences(of: "\"", with: "\\\"")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "display notification \"\(escaped)\" with title \"\(title)\""]
        try? process.run()
    }

    private static func postBundleNotification(_ message: String, title: String) -> Bool {
        guard Bundle.main.bundlePath.hasSuffix(".app") else { return false }
        let center = UNUserNotificationCenter.current()
        var granted = false
        let authWait = DispatchSemaphore(value: 0)
        center.requestAuthorization(options: [.alert]) { ok, _ in
            granted = ok
            authWait.signal()
        }
        _ = authWait.wait(timeout: .now() + 30)
        guard granted else { return false }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        return true
    }
}
```

- [ ] **Step 2: Implement AppState**

`Sources/GitHubTouch/AppState.swift`:

```swift
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
```

- [ ] **Step 3: Implement the menu and wire the app scene**

`Sources/GitHubTouch/MenuContentView.swift`:

```swift
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
```

Replace the body of `Sources/GitHubTouch/GitHubTouchApp.swift`:

```swift
import SwiftUI

struct GitHubTouchApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView().environmentObject(state)
        } label: {
            Image(systemName: "touchid")
                .opacity(state.activation.isActive ? 1.0 : 0.45)
        }
        Window("Add Token", id: "add-token") {
            Text("Add Token — coming in Task 8").padding().frame(width: 300)
        }
        .windowResizability(.contentSize)
        Window("Manage Tokens", id: "manage-tokens") {
            Text("Manage — coming in Task 10").padding().frame(width: 300)
        }
        .windowResizability(.contentSize)
    }
}
```

- [ ] **Step 4: Build, run tests, and verify manually**

Run: `swift build && swift test 2>&1 | tail -3`
Expected: build succeeds, `Executed 25 tests, with 0 failures`.

Run: `./build.sh && open ~/Applications/"GitHub Touch.app"`
Manual checks:
1. Menu shows "No token active" and "No tokens in the vault yet" (dimmed icon).
2. "Add Token…" opens the placeholder window in front.
3. Quit works.

- [ ] **Step 5: Commit**

```bash
git add Sources
git commit -m "feat: menu bar UI with activation lifecycle and midnight clearing"
```

---

### Task 8: Guided token generation (Add Token window)

**Files:**
- Create: `Sources/GitHubTouchCore/TokenURLBuilder.swift`
- Create: `Sources/GitHubTouch/AddTokenView.swift`
- Modify: `Sources/GitHubTouch/GitHubTouchApp.swift` (swap placeholder for `AddTokenView`)
- Test: `Tests/GitHubTouchCoreTests/TokenURLBuilderTests.swift`

**Interfaces:**
- Consumes: `TokenKind`, `TokenInfo`, `TokenValidator`, `AppState.addToken` (Tasks 2, 5, 7).
- Produces:
  - `TokenURLBuilder.classicNewTokenURL(scopes: [String], description: String) -> URL`.
  - `TokenURLBuilder.fineGrainedNewTokenURL: URL`.
  - `TokenURLBuilder.classicScopeChoices: [(scope: String, help: String)]`.

- [ ] **Step 1: Write the failing tests**

`Tests/GitHubTouchCoreTests/TokenURLBuilderTests.swift`:

```swift
import XCTest
@testable import GitHubTouchCore

final class TokenURLBuilderTests: XCTestCase {
    func testClassicURLEncodesScopesAndDescription() {
        let url = TokenURLBuilder.classicNewTokenURL(
            scopes: ["repo", "read:org"], description: "CI helper & tools")
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        XCTAssertEqual(components.host, "github.com")
        XCTAssertEqual(components.path, "/settings/tokens/new")
        let query = Dictionary(uniqueKeysWithValues: components.queryItems!.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(query["scopes"], "repo,read:org")
        XCTAssertEqual(query["description"], "CI helper & tools")
    }

    func testFineGrainedURL() {
        XCTAssertEqual(TokenURLBuilder.fineGrainedNewTokenURL.absoluteString,
                       "https://github.com/settings/personal-access-tokens/new")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter TokenURLBuilderTests 2>&1 | tail -5`
Expected: compilation failure — `TokenURLBuilder` not defined.

- [ ] **Step 3: Implement TokenURLBuilder**

`Sources/GitHubTouchCore/TokenURLBuilder.swift`:

```swift
import Foundation

public enum TokenURLBuilder {
    public static let fineGrainedNewTokenURL =
        URL(string: "https://github.com/settings/personal-access-tokens/new")!

    /// github.com pre-fills the classic-token form from these query params.
    public static func classicNewTokenURL(scopes: [String], description: String) -> URL {
        var components = URLComponents(string: "https://github.com/settings/tokens/new")!
        components.queryItems = [
            URLQueryItem(name: "scopes", value: scopes.joined(separator: ",")),
            URLQueryItem(name: "description", value: description),
        ]
        return components.url!
    }

    public static let classicScopeChoices: [(scope: String, help: String)] = [
        ("repo", "full read/write on ALL repos"),
        ("public_repo", "read/write on public repos only"),
        ("gist", "create and edit gists"),
        ("workflow", "update GitHub Actions workflows"),
        ("read:org", "read org membership"),
        ("admin:org", "manage org settings"),
        ("notifications", "read notifications"),
        ("delete_repo", "delete repositories"),
    ]
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test 2>&1 | tail -3`
Expected: `Executed 27 tests, with 0 failures`.

- [ ] **Step 5: Implement AddTokenView**

`Sources/GitHubTouch/AddTokenView.swift`:

```swift
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
```

In `GitHubTouchApp.swift`, replace the add-token placeholder window content:

```swift
        Window("Add Token", id: "add-token") {
            AddTokenView().environmentObject(state)
        }
        .windowResizability(.contentSize)
```

- [ ] **Step 6: Build and verify manually**

Run: `swift build && swift test 2>&1 | tail -3` — expect 27 tests passing.
Run: `./build.sh && open ~/Applications/"GitHub Touch.app"`
Manual checks:
1. "Add Token…" opens the form; choosing Classic reveals scope checkboxes.
2. "Open GitHub…" with classic + `repo` + label "test" opens the browser with scopes and description pre-filled.
3. Pasting garbage and clicking Validate shows the 401 error; nothing can be saved.
4. Full happy path (with a real short-expiry token): validate → green line with login → Save → token appears in the menu (first save also creates the Secure Enclave key). Activate it (Touch ID) → `gh auth status` in a terminal shows logged in → "Deactivate Now" → logged out.

- [ ] **Step 7: Commit**

```bash
git add Sources Tests
git commit -m "feat: guided token generation and add-token window"
```

---

### Task 9: Import the existing keychain token (first-run migration)

**Files:**
- Create: `Sources/GitHubTouch/ImportTokenView.swift`
- Modify: `Sources/GitHubTouch/GitHubTouchApp.swift` (add window scene)
- Modify: `Sources/GitHubTouch/MenuContentView.swift` (conditional menu item)
- Modify: `Sources/GitHubTouch/AppState.swift` (add `importCurrentToken`)

**Interfaces:**
- Consumes: `GhBridge.currentToken()/isLoggedIn()/deactivate()`, `TokenValidator`, `AppState.addToken` (Tasks 4, 5, 7).
- Produces: `AppState.canImportExistingToken: Bool`, `AppState.importCurrentToken() async throws -> String` (returns the created label).

- [ ] **Step 1: Add import logic to AppState**

Append to `Sources/GitHubTouch/AppState.swift`:

```swift
extension AppState {
    /// Offer the migration while the vault has no tokens but gh is still logged in.
    var canImportExistingToken: Bool {
        tokens.isEmpty && (gh?.isLoggedIn() ?? false)
    }

    enum ImportError: LocalizedError {
        case noToken
        var errorDescription: String? { "gh reported no current token." }
    }

    func importCurrentToken() async throws -> String {
        guard let gh, let token = await Task.detached(operation: { gh.currentToken() }).value else {
            throw ImportError.noToken
        }
        let info = try await TokenValidator().validate(token)
        let label = "full access (legacy OAuth)"
        try addToken(label: label, kind: .oauth,
                     permissions: info.scopes ?? [],
                     expiresAt: info.expiresAt,
                     notes: "imported from gh keychain on \(Date().formatted(date: .abbreviated, time: .omitted))",
                     secret: token)
        try await Task.detached { try gh.deactivate() }.value
        activation = ActivationState()
        stateStore.save(activation)
        return label
    }
}
```

- [ ] **Step 2: Implement ImportTokenView**

`Sources/GitHubTouch/ImportTokenView.swift`:

```swift
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
```

- [ ] **Step 3: Wire it into menu and scenes**

In `MenuContentView.swift`, insert directly under `header` / before the first `Divider()`:

```swift
            if state.canImportExistingToken {
                Button("Import current gh token…") { open(windowId: "import-token") }
            }
```

In `GitHubTouchApp.swift`, add alongside the other `Window` scenes:

```swift
        Window("Import Token", id: "import-token") {
            ImportTokenView().environmentObject(state)
        }
        .windowResizability(.contentSize)
```

- [ ] **Step 4: Build and verify manually**

Run: `swift build && swift test 2>&1 | tail -3` — all tests still pass.
Run: `./build.sh && open ~/Applications/"GitHub Touch.app"`
Manual checks (do this while the old `gho_` token is still in the keychain and the vault has no tokens):
1. Menu shows "Import current gh token…".
2. Click → window explains the move → "Import & Log gh Out".
3. Afterwards: `gh auth status` in a terminal reports logged out; the menu lists "full access (legacy OAuth)" with the captured scopes; the import menu item is gone.
4. Activate it via Touch ID → `gh auth status` shows logged in again.

- [ ] **Step 5: Commit**

```bash
git add Sources
git commit -m "feat: first-run import of the existing gh keychain token"
```

---

### Task 10: Manage window (rename, edit metadata, delete)

**Files:**
- Create: `Sources/GitHubTouch/ManageView.swift`
- Modify: `Sources/GitHubTouch/GitHubTouchApp.swift` (swap placeholder for `ManageView`)

**Interfaces:**
- Consumes: `AppState.updateMetadata`, `AppState.deleteToken`, `TokenEntry` (Tasks 2, 7).
- Produces: nothing consumed later.

- [ ] **Step 1: Implement ManageView**

`Sources/GitHubTouch/ManageView.swift`:

```swift
import GitHubTouchCore
import SwiftUI

struct ManageView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        List(state.tokens) { token in
            TokenRowEditor(token: token)
        }
        .frame(width: 520, height: max(200, CGFloat(state.tokens.count) * 130))
    }
}

private struct TokenRowEditor: View {
    @EnvironmentObject var state: AppState
    let token: TokenEntry
    @State private var label: String
    @State private var permissionsText: String
    @State private var notes: String
    @State private var confirmingDelete = false

    init(token: TokenEntry) {
        self.token = token
        _label = State(initialValue: token.label)
        _permissionsText = State(initialValue: token.permissions.joined(separator: ", "))
        _notes = State(initialValue: token.notes)
    }

    private var dirty: Bool {
        label != token.label
            || permissionsText != token.permissions.joined(separator: ", ")
            || notes != token.notes
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
            TextField("Permissions (comma-separated)", text: $permissionsText)
            TextField("Notes", text: $notes)
            HStack {
                Button("Delete…", role: .destructive) { confirmingDelete = true }
                    .confirmationDialog("Delete “\(token.label)” from the vault?",
                                        isPresented: $confirmingDelete) {
                        Button("Delete", role: .destructive) { state.deleteToken(id: token.id) }
                    } message: {
                        Text("The token itself keeps working on GitHub until you revoke it there.")
                    }
                Spacer()
                Button("Save Changes") {
                    let permissions = permissionsText.split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    state.updateMetadata(id: token.id, label: label,
                                         permissions: permissions, notes: notes)
                }
                .disabled(!dirty)
            }
        }
        .padding(.vertical, 8)
    }
}
```

In `GitHubTouchApp.swift`, replace the manage placeholder window content:

```swift
        Window("Manage Tokens", id: "manage-tokens") {
            ManageView().environmentObject(state)
        }
        .windowResizability(.contentSize)
```

- [ ] **Step 2: Build and verify manually**

Run: `swift build && ./build.sh && open ~/Applications/"GitHub Touch.app"`
Manual checks:
1. "Manage Tokens…" lists every vault entry with kind and expiry.
2. Rename a token, Save Changes → the menu shows the new label; `vault.json` reflects it; the ciphertext fields are unchanged.
3. Delete asks for confirmation and removes the entry.

- [ ] **Step 3: Commit**

```bash
git add Sources
git commit -m "feat: manage window for token metadata and deletion"
```

---

### Task 11: Icons — app icon and menu bar template glyph

**Files:**
- Create: `icons/a-print-key.svg`, `icons/b-print-badge.svg` (candidates; the chosen one is referenced by `make-icns.sh`)
- Create: `icons/menubar.svg`
- Create: `icons/make-icns.sh`
- Modify: `Sources/GitHubTouch/GitHubTouchApp.swift` (custom menu bar image with SF Symbol fallback)

**Interfaces:**
- Consumes: `build.sh` already copies `icons/AppIcon.icns` and `icons/MenuIconTemplate*.png` into the bundle (Task 1).
- Produces: `icons/AppIcon.icns`, `icons/MenuIconTemplate.png` (18×18), `icons/MenuIconTemplate@2x.png` (36×36).

- [ ] **Step 1: Write the icon SVG candidates**

Theme: **"the fingerprint is the key"** — a key whose bow is a fingerprint whorl, warm orange on a dark tile, visually related to ssh-touch-add's "Prompt" icon.

`icons/a-print-key.svg`:

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
  <rect x="64" y="64" width="896" height="896" rx="200" fill="#14171d"/>
  <g fill="none" stroke="#e8833a" stroke-linecap="round">
    <!-- key bow drawn as fingerprint ridges -->
    <circle cx="420" cy="420" r="60"  stroke-width="30" stroke-dasharray="283 94"  transform="rotate(-30 420 420)"/>
    <circle cx="420" cy="420" r="120" stroke-width="30" stroke-dasharray="565 189" transform="rotate(80 420 420)"/>
    <circle cx="420" cy="420" r="180" stroke-width="30" stroke-dasharray="848 283" transform="rotate(200 420 420)"/>
    <!-- shaft and teeth -->
    <path d="M560 560 L800 800" stroke-width="56"/>
    <path d="M716 716 L660 772" stroke-width="44"/>
    <path d="M800 800 L744 856" stroke-width="44"/>
  </g>
</svg>
```

`icons/b-print-badge.svg` (fingerprint filling the tile, small solid key in the corner):

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
  <rect x="64" y="64" width="896" height="896" rx="200" fill="#14171d"/>
  <g fill="none" stroke="#e8833a" stroke-linecap="round">
    <circle cx="512" cy="480" r="70"  stroke-width="34" stroke-dasharray="330 110" transform="rotate(20 512 480)"/>
    <circle cx="512" cy="480" r="150" stroke-width="34" stroke-dasharray="707 236" transform="rotate(140 512 480)"/>
    <circle cx="512" cy="480" r="230" stroke-width="34" stroke-dasharray="1084 361" transform="rotate(260 512 480)"/>
  </g>
  <g stroke="#8b949e" stroke-width="34" stroke-linecap="round" fill="none">
    <circle cx="700" cy="768" r="46"/>
    <path d="M740 808 L850 918 M810 878 L770 918"/>
  </g>
</svg>
```

`icons/menubar.svg` (pure black on transparent — macOS template image; simplified so it stays crisp at 18 pt):

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 36 36">
  <g fill="none" stroke="#000" stroke-width="3" stroke-linecap="round">
    <circle cx="14" cy="14" r="4"  stroke-dasharray="19 6"  transform="rotate(-30 14 14)"/>
    <circle cx="14" cy="14" r="9.5" stroke-dasharray="45 15" transform="rotate(100 14 14)"/>
    <path d="M21 21 L31 31"/>
    <path d="M27.5 27.5 L24 31"/>
  </g>
</svg>
```

- [ ] **Step 2: Write make-icns.sh**

`icons/make-icns.sh` (adapted from `../ssh-touch-add/icons/make-icns.sh`):

```bash
#!/bin/bash
# Render the chosen SVG into AppIcon.icns and the menu bar template PNGs.
set -euo pipefail
cd "$(dirname "$0")"
CHOSEN=a-print-key.svg

rm -rf AppIcon.iconset app-1024.png
qlmanage -t -s 1024 -o . "$CHOSEN" >/dev/null
mv "$CHOSEN.png" app-1024.png

mkdir AppIcon.iconset
for size in 16 32 128 256 512; do
  sips -z $size $size app-1024.png --out "AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z $double $double app-1024.png --out "AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns AppIcon.iconset -o AppIcon.icns
rm -rf AppIcon.iconset app-1024.png

qlmanage -t -s 36 -o . menubar.svg >/dev/null
mv menubar.svg.png MenuIconTemplate@2x.png
sips -z 18 18 MenuIconTemplate@2x.png --out MenuIconTemplate.png >/dev/null
echo "AppIcon.icns and MenuIconTemplate PNGs written."
```

Then: `chmod +x icons/make-icns.sh && icons/make-icns.sh`

- [ ] **Step 3: Look at both app icon candidates and pick**

Run: `for f in icons/[ab]-*.svg; do qlmanage -t -s 512 -o /tmp/claude-icons "$f"; done 2>/dev/null; open /tmp/claude-icons`
(Create the output dir first if needed.) Compare, adjust the SVG geometry if the fingerprint ridges or key shaft look off (this step is expected to iterate a couple of times), set `CHOSEN` in `make-icns.sh` to the winner, re-run it.

- [ ] **Step 4: Use the template glyph in the menu bar, with SF Symbol fallback**

In `GitHubTouchApp.swift`, replace the `label:` closure of `MenuBarExtra`:

```swift
        } label: {
            MenuBarIcon(active: state.activation.isActive)
        }
```

and add to the same file:

```swift
struct MenuBarIcon: View {
    let active: Bool

    var body: some View {
        if let path = Bundle.main.path(forResource: "MenuIconTemplate", ofType: "png"),
           let image = NSImage(contentsOfFile: path) {
            let _ = { image.isTemplate = true }()
            Image(nsImage: image).opacity(active ? 1.0 : 0.45)
        } else {
            // dev runs from the bare binary have no bundle resources
            Image(systemName: "touchid").opacity(active ? 1.0 : 0.45)
        }
    }
}
```

- [ ] **Step 5: Build and verify visually**

Run: `./build.sh && open ~/Applications/"GitHub Touch.app"`
Manual checks:
1. The app icon shows in Finder/Spotlight for `GitHub Touch.app` (Finder may need a `killall Finder` to drop its icon cache).
2. The menu bar glyph is crisp in both light and dark menu bars; if it reads muddy at 18 pt, keep the SF Symbol branch instead (delete the PNGs and note the decision in the README in Task 12).
3. Activating a token brightens the glyph; deactivating dims it.

- [ ] **Step 6: Commit**

```bash
git add icons Sources build.sh
git commit -m "feat: fingerprint-key app icon and menu bar template glyph"
```

---

### Task 12: Launch at login, SE plumbing self-test, debug clear, README

**Files:**
- Create: `Sources/GitHubTouch/LaunchAtLoginToggle.swift`
- Modify: `Sources/GitHubTouch/Main.swift` (`--test-plumbing`)
- Modify: `Sources/GitHubTouch/MenuContentView.swift` (toggle + debug item)
- Modify: `build.sh` (run the plumbing test after install)
- Create: `README.md`

**Interfaces:**
- Consumes: `SecureEnclaveVaultKey`, `VaultCrypto` (Task 2), `AppState.scheduleClear` (Task 7).
- Produces: final deliverable; nothing consumed later.

- [ ] **Step 1: Add the --test-plumbing entry point**

`Sources/GitHubTouch/Main.swift` becomes:

```swift
import Foundation
import GitHubTouchCore

@main
enum Main {
    static func main() {
        if CommandLine.arguments.contains("--test-plumbing") {
            testPlumbing()
        }
        GitHubTouchApp.main()
    }

    // Round-trips a secret through the real Secure Enclave (no Touch ID gate)
    // to prove the production code path works on this machine.
    static func testPlumbing() -> Never {
        do {
            let key = try SecureEnclaveVaultKey.create(requireUserPresence: false)
            let sealed = try VaultCrypto.seal("test-secret-🔑", recipientPub: key.x963PublicKey)
            let out = try VaultCrypto.unseal(
                ciphertext: sealed.ciphertext, ephemeralPub: sealed.ephemeralPub, using: key)
            print(out == "test-secret-🔑"
                  ? "OK: Secure Enclave round-trip succeeded"
                  : "FAIL: decrypted value mismatch")
            exit(out == "test-secret-🔑" ? 0 : 1)
        } catch {
            print("FAIL: \(error)")
            exit(1)
        }
    }
}
```

In `build.sh`, add before the final `echo`:

```bash
"./$APP/Contents/MacOS/GitHubTouch" --test-plumbing
```

Run: `./build.sh`
Expected: `OK: Secure Enclave round-trip succeeded` before the install message.

- [ ] **Step 2: Launch-at-login toggle**

`Sources/GitHubTouch/LaunchAtLoginToggle.swift`:

```swift
import ServiceManagement
import SwiftUI

struct LaunchAtLoginToggle: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled

    var body: some View {
        Toggle("Start at Login", isOn: $enabled)
            .onChange(of: enabled) { turnOn in
                do {
                    if turnOn {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    enabled = SMAppService.mainApp.status == .enabled
                }
            }
    }
}
```

In `MenuContentView.swift`, insert above the Quit button:

```swift
            LaunchAtLoginToggle()
            #if DEBUG
            Button("Debug: Clear in 1 Minute") {
                state.scheduleClear(at: Date(timeIntervalSinceNow: 60))
            }
            #endif
```

(The debug item only exists in `swift build` debug builds; `build.sh` builds `-c release`, so users never see it. Note: it only reschedules the timer — the overdue check still compares against the persisted `clearAt`, so also set it via a temporary activation when testing.)

Correction so the debug path actually clears: make the debug button set the real deadline:

```swift
            #if DEBUG
            Button("Debug: Clear in 1 Minute") {
                var s = state.activation
                s.clearAt = Date(timeIntervalSinceNow: 60)
                state.activation = s
                state.stateStore.save(s)
                state.scheduleClear(at: s.clearAt!)
            }
            #endif
```

(`stateStore` must be `let stateStore` without `private` in `AppState` — it already is per Task 7.)

- [ ] **Step 3: Manual lifecycle verification**

Build a **debug** bundle for this test: temporarily change `swift build -c release` to `swift build` and `BIN=.build/debug/GitHubTouch` in `build.sh`, run `./build.sh`, then:

1. Activate a token (Touch ID) → `gh auth status` logged in.
2. "Debug: Clear in 1 Minute" → wait 60 s → notification, `gh auth status` logged out, icon dims.
3. Activate again, then "Debug: Clear in 1 Minute", quit the app before the minute passes, wait, relaunch → the launch check clears it immediately.
4. Revert `build.sh` to `-c release` and run `./build.sh` again.

- [ ] **Step 4: Write README.md**

```markdown
# GitHub Touch

A menu bar app that keeps GitHub tokens in a Touch ID vault and never
leaves one lying around: pick a token from the menu, touch the sensor,
and it's live in `gh`'s keychain — until midnight, when it is cleared.

## Why

`gh auth login` parks a broad, non-expiring token in the keychain
forever. GitHub Touch replaces that with a set of purpose-scoped tokens
(fine-grained or classic PATs) stored encrypted under a Secure Enclave
key. Only the one you activate exists outside the vault, and only until
midnight.

## How it works

- Tokens are AES-GCM-encrypted, each under its own ephemeral ECDH
  against a P-256 key that lives in this Mac's Secure Enclave with a
  `userPresence` access control (Touch ID, password fallback). Only
  ciphertext and metadata hit disk:
  `~/Library/Application Support/github-touch/vault.json` (mode 600).
- Activating runs `gh auth login --with-token` with the token piped via
  stdin — it never appears on a command line or in a file.
- Clearing runs `gh auth logout`. It fires at midnight if the app is
  running, on wake if the Mac slept through it, and at launch if the
  app wasn't running. "Deactivate Now" does it on demand.
- Metadata (label, permissions, expiry, notes) is deliberately stored
  in plaintext so the menu can show what each token can do without
  prompting.

## Honest caveat

While a token is active it sits in the keychain exactly as exposed as
a normal `gh auth login`. The win is least-privilege scoping plus a
guaranteed daily expiry — not runtime protection of the active token.

## Installed pieces

| Path | What |
|---|---|
| `~/Applications/GitHub Touch.app` | the menu bar app (LSUIElement) |
| `~/Library/Application Support/github-touch/vault.json` | encrypted tokens + metadata |

## Rebuilding

```sh
./build.sh   # swift build -c release, bundle, sign, install, SE self-test
swift test   # core library unit tests
```

The Secure Enclave key blob is not tied to the code signature, so
rebuilding does not require re-enrolling tokens. The vault is useless
off this machine.

## Manual test checklist

1. Add a token (guided): Add Token… → Open GitHub… → paste → validate → save.
2. Activate it: Touch ID → `gh auth status` shows logged in.
3. Deactivate Now → logged out, icon dims.
4. Midnight: activate, set the clock or use the debug build's
   "Clear in 1 Minute", confirm the logout fires — including after quit
   + relaunch, and after sleep + wake.
5. Revoking: delete a vault entry, then revoke the token on
   github.com/settings/tokens (deleting here does not revoke there).
```

- [ ] **Step 5: Final verification**

Run: `swift test 2>&1 | tail -3` — all tests pass.
Run: `./build.sh` — ends with `OK: Secure Enclave round-trip succeeded` and the install message.
Launch from Spotlight, run through README checklist items 1–3.

- [ ] **Step 6: Commit**

```bash
git add Sources build.sh README.md
git commit -m "feat: launch at login, SE self-test, debug clear, README"
```

---

## Self-review notes

- **Spec coverage:** activation via keychain/gh (T4/T7), both PAT kinds + guided generation (T8), legacy import (T9), metadata memory + manage (T2/T10), midnight/wake/launch clearing (T6/T7), icons (T11), errors incl. corrupt-vault reset and gh-missing (T7), security properties (T4 stdin test, T3 0600 test), README caveat (T12). Out-of-scope list respected — no multi-account, no revocation, no countdown.
- **Type consistency:** `x963PublicKey` (protocol property), `permissionSummary`, `scheduleClear(at:)`, `stateStore` non-private — checked against each consuming task.
- **Known judgment calls:** menu-bar `.menu` style constrains rows to simple Buttons; icon SVGs are starting points with an explicit iterate step; `MenuBarIcon` falls back to the `touchid` SF Symbol per spec.
