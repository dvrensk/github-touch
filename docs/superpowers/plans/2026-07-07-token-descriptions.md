# Auto-generated Token Descriptions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a token is added or imported, GitHub Touch generates its menu one-liner and capability details itself — from the scope table (classic/OAuth) or a read-only API probe (fine-grained) — with the user able to edit before saving.

**Architecture:** Three pure/core units in GitHubTouchCore (`ScopeCatalog` lookup table, `CapabilityProber` async prober, `DescriptionBuilder` pure formatter), a backward-compatible optional `summary` field on `TokenEntry`, and wiring in AddTokenView/import/Manage. No LLM, no new dependencies.

**Tech Stack:** Swift 5.10, Foundation URLSession (async), XCTest with the existing `MockURLProtocol` pattern.

**Spec:** `docs/superpowers/specs/2026-07-07-token-descriptions-design.md`
**Branch:** feature/github-touch (continue on it). Suite currently 29 tests green.

## Global Constraints

- No third-party dependencies; no LLM/OpenRouter integration.
- Token strings stay in memory only: never argv, file, pasteboard, log, or notification text.
- Probes are read-only GETs against `https://api.github.com`, 5-second per-request timeout, concurrent, fine-grained tokens only, once at add-time.
- `TokenEntry.summary` is `String?` and must decode from vault.json files that lack the key (no vault version bump).
- Summary length target ≤ 60 characters, truncated at a word boundary with "…".
- Dangerous capabilities are prefixed "⚠ " in generated text.
- Commit after every task with trailer `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.

---

### Task 1: ScopeCatalog

**Files:**
- Create: `Sources/GitHubTouchCore/ScopeCatalog.swift`
- Test: `Tests/GitHubTouchCoreTests/ScopeCatalogTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `ScopeCatalog.describe(_ scope: String) -> (phrase: String, dangerous: Bool)` — exact-string lookup, unknown scopes pass through verbatim as `(scope, false)`.

- [ ] **Step 1: Write the failing tests**

`Tests/GitHubTouchCoreTests/ScopeCatalogTests.swift`:

```swift
import XCTest
@testable import GitHubTouchCore

final class ScopeCatalogTests: XCTestCase {
    func testKnownScopes() {
        XCTAssertEqual(ScopeCatalog.describe("repo").phrase, "read/write ALL repos")
        XCTAssertTrue(ScopeCatalog.describe("repo").dangerous)
        XCTAssertEqual(ScopeCatalog.describe("gist").phrase, "gists")
        XCTAssertFalse(ScopeCatalog.describe("gist").dangerous)
        XCTAssertTrue(ScopeCatalog.describe("delete_repo").dangerous)
        XCTAssertTrue(ScopeCatalog.describe("admin:org").dangerous)
        XCTAssertFalse(ScopeCatalog.describe("read:org").dangerous)
    }

    func testUnknownScopePassesThroughVerbatim() {
        let result = ScopeCatalog.describe("codespace")
        XCTAssertEqual(result.phrase, "codespace")
        XCTAssertFalse(result.dangerous)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ScopeCatalogTests 2>&1 | tail -5`
Expected: compilation failure — `ScopeCatalog` not defined.

- [ ] **Step 3: Implement ScopeCatalog**

`Sources/GitHubTouchCore/ScopeCatalog.swift`:

```swift
import Foundation

/// Plain-English phrases for classic/OAuth token scopes, per the spec's table.
public enum ScopeCatalog {
    static let table: [String: (phrase: String, dangerous: Bool)] = [
        "repo": ("read/write ALL repos", true),
        "public_repo": ("read/write public repos", false),
        "delete_repo": ("delete repos", true),
        "admin:org": ("manage org", true),
        "write:org": ("write org data", true),
        "read:org": ("read org membership", false),
        "gist": ("gists", false),
        "workflow": ("edit Actions workflows", true),
        "notifications": ("notifications", false),
        "user": ("read profile", false),
        "read:user": ("read profile", false),
        "user:email": ("read email", false),
    ]

    public static func describe(_ scope: String) -> (phrase: String, dangerous: Bool) {
        table[scope] ?? (scope, false)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test 2>&1 | grep -E "Executed .* tests" | tail -1`
Expected: `Executed 31 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/GitHubTouchCore/ScopeCatalog.swift Tests/GitHubTouchCoreTests/ScopeCatalogTests.swift
git commit -m "feat: scope catalog mapping classic scopes to plain English"
```

---

### Task 2: CapabilityProber

**Files:**
- Create: `Sources/GitHubTouchCore/CapabilityProber.swift`
- Test: `Tests/GitHubTouchCoreTests/CapabilityProberTests.swift`

**Interfaces:**
- Consumes: `TokenValidationError.invalidToken` (exists), test-target `MockURLProtocol` (exists in `Tests/GitHubTouchCoreTests/TokenValidatorTests.swift`, internal to the test target — reusable).
- Produces:
  - `ProbeOutcome: Equatable, Sendable` — `.granted(detail: [String]?)`, `.denied(needed: String?)`, `.unknown`.
  - `ProbeReport: Equatable, Sendable` — `repos, orgs, gists, notifications, emails: ProbeOutcome`; `init` defaulting all to `.unknown`.
  - `CapabilityProber` — `init(session: URLSession = .shared)`, `func probe(_ token: String) async throws -> ProbeReport` (throws `TokenValidationError.invalidToken` if any probe returns 401).

- [ ] **Step 1: Write the failing tests**

`Tests/GitHubTouchCoreTests/CapabilityProberTests.swift` (routes `MockURLProtocol` by path; probes run concurrently, so the handler must be pure routing set once per test):

```swift
import XCTest
@testable import GitHubTouchCore

final class CapabilityProberTests: XCTestCase {
    var prober: CapabilityProber!

    override func setUp() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        prober = CapabilityProber(session: URLSession(configuration: config))
    }

    func route(_ responses: [String: (Int, [String: String], String)]) {
        MockURLProtocol.handler = { request in
            let path = request.url!.path
            let (status, headers, body) = responses[path] ?? (404, [:], "{}")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok123")
            let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                           httpVersion: nil, headerFields: headers)!
            return (response, Data(body.utf8))
        }
    }

    func testAllGrantedWithRepoNames() async throws {
        route([
            "/user/repos": (200, [:], #"[{"name":"api"},{"name":"web"},{"name":"infra"}]"#),
            "/user/orgs": (200, [:], "[]"),
            "/gists": (200, [:], "[]"),
            "/notifications": (200, [:], "[]"),
            "/user/emails": (200, [:], "[]"),
        ])
        let report = try await prober.probe("tok123")
        XCTAssertEqual(report.repos, .granted(detail: ["api", "web", "infra"]))
        XCTAssertEqual(report.orgs, .granted(detail: nil))
        XCTAssertEqual(report.emails, .granted(detail: nil))
    }

    func testDeniedRecordsNeededPermissionsHeader() async throws {
        route([
            "/user/repos": (200, [:], "[]"),
            "/user/orgs": (403, ["X-Accepted-GitHub-Permissions": "members=read"], "{}"),
            "/gists": (403, [:], "{}"),
            "/notifications": (200, [:], "[]"),
            "/user/emails": (200, [:], "[]"),
        ])
        let report = try await prober.probe("tok123")
        XCTAssertEqual(report.orgs, .denied(needed: "members=read"))
        XCTAssertEqual(report.gists, .denied(needed: nil))
        XCTAssertEqual(report.repos, .granted(detail: []))
    }

    func testUnexpectedStatusIsUnknown() async throws {
        route([
            "/user/repos": (500, [:], "{}"),
            "/user/orgs": (200, [:], "[]"),
            "/gists": (200, [:], "[]"),
            "/notifications": (200, [:], "[]"),
            "/user/emails": (200, [:], "[]"),
        ])
        let report = try await prober.probe("tok123")
        XCTAssertEqual(report.repos, .unknown)
    }

    func testAnyUnauthorizedThrowsInvalidToken() async {
        route([
            "/user/repos": (401, [:], "{}"),
            "/user/orgs": (200, [:], "[]"),
            "/gists": (200, [:], "[]"),
            "/notifications": (200, [:], "[]"),
            "/user/emails": (200, [:], "[]"),
        ])
        do {
            _ = try await prober.probe("tok123")
            XCTFail("should throw")
        } catch let error as TokenValidationError {
            XCTAssertEqual(error, .invalidToken)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter CapabilityProberTests 2>&1 | tail -5`
Expected: compilation failure — `CapabilityProber` not defined.

- [ ] **Step 3: Implement CapabilityProber**

`Sources/GitHubTouchCore/CapabilityProber.swift`:

```swift
import Foundation

public enum ProbeOutcome: Equatable, Sendable {
    case granted(detail: [String]?)  // repo names for the repos probe, nil elsewhere
    case denied(needed: String?)     // X-Accepted-GitHub-Permissions header when present
    case unknown                     // network error, timeout, or unexpected status
}

public struct ProbeReport: Equatable, Sendable {
    public var repos: ProbeOutcome
    public var orgs: ProbeOutcome
    public var gists: ProbeOutcome
    public var notifications: ProbeOutcome
    public var emails: ProbeOutcome

    public init(repos: ProbeOutcome = .unknown, orgs: ProbeOutcome = .unknown,
                gists: ProbeOutcome = .unknown, notifications: ProbeOutcome = .unknown,
                emails: ProbeOutcome = .unknown) {
        self.repos = repos
        self.orgs = orgs
        self.gists = gists
        self.notifications = notifications
        self.emails = emails
    }
}

/// Discovers what a fine-grained token can read by trying cheap, read-only
/// endpoints. Write access is never probed (probing would mutate).
public struct CapabilityProber {
    let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    enum Endpoint: String, CaseIterable {
        case repos = "/user/repos?per_page=100"
        case orgs = "/user/orgs"
        case gists = "/gists"
        case notifications = "/notifications"
        case emails = "/user/emails"
    }

    public func probe(_ token: String) async throws -> ProbeReport {
        var outcomes: [Endpoint: ProbeOutcome] = [:]
        try await withThrowingTaskGroup(of: (Endpoint, ProbeOutcome).self) { group in
            for endpoint in Endpoint.allCases {
                group.addTask { (endpoint, try await probeOne(endpoint, token: token)) }
            }
            for try await (endpoint, outcome) in group {
                outcomes[endpoint] = outcome
            }
        }
        return ProbeReport(repos: outcomes[.repos] ?? .unknown,
                           orgs: outcomes[.orgs] ?? .unknown,
                           gists: outcomes[.gists] ?? .unknown,
                           notifications: outcomes[.notifications] ?? .unknown,
                           emails: outcomes[.emails] ?? .unknown)
    }

    private func probeOne(_ endpoint: Endpoint, token: String) async throws -> ProbeOutcome {
        var request = URLRequest(url: URL(string: "https://api.github.com" + endpoint.rawValue)!)
        request.timeoutInterval = 5
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            return .unknown
        }
        guard let http = response as? HTTPURLResponse else { return .unknown }
        switch http.statusCode {
        case 200:
            guard endpoint == .repos else { return .granted(detail: nil) }
            struct Repo: Decodable { let name: String }
            let names = (try? JSONDecoder().decode([Repo].self, from: data))?.map(\.name) ?? []
            return .granted(detail: names)
        case 401:
            throw TokenValidationError.invalidToken
        case 403, 404:
            // fine-grained tokens get 403 (or 404 on some endpoints) when the
            // permission is missing
            return .denied(needed: http.value(forHTTPHeaderField: "X-Accepted-GitHub-Permissions"))
        default:
            return .unknown
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test 2>&1 | grep -E "Executed .* tests" | tail -1`
Expected: `Executed 35 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/GitHubTouchCore/CapabilityProber.swift Tests/GitHubTouchCoreTests/CapabilityProberTests.swift
git commit -m "feat: read-only capability prober for fine-grained tokens"
```

---

### Task 3: DescriptionBuilder

**Files:**
- Create: `Sources/GitHubTouchCore/DescriptionBuilder.swift`
- Modify: `docs/superpowers/specs/2026-07-07-token-descriptions-design.md` (drop one clause, see Step 5)
- Test: `Tests/GitHubTouchCoreTests/DescriptionBuilderTests.swift`

**Interfaces:**
- Consumes: `ScopeCatalog.describe` (Task 1), `ProbeReport`/`ProbeOutcome` (Task 2), `TokenKind` (exists).
- Produces: `DescriptionBuilder.build(kind: TokenKind, scopes: [String]?, probe: ProbeReport?, expiresAt: Date?) -> (summary: String, details: [String])` and (internal, tested) `DescriptionBuilder.truncate(_ s: String, to limit: Int) -> String`.

- [ ] **Step 1: Write the failing tests**

`Tests/GitHubTouchCoreTests/DescriptionBuilderTests.swift`:

```swift
import XCTest
@testable import GitHubTouchCore

final class DescriptionBuilderTests: XCTestCase {
    func testClassicScopesMapWithDangerFlags() {
        let result = DescriptionBuilder.build(kind: .classic, scopes: ["repo", "gist"],
                                              probe: nil, expiresAt: nil)
        XCTAssertEqual(result.summary, "⚠ read/write ALL repos, gists")
        XCTAssertEqual(result.details, ["⚠ read/write ALL repos", "gists"])
    }

    func testExpiryAppendedToDetails() {
        let expiry = Date(timeIntervalSince1970: 1_790_000_000)
        let result = DescriptionBuilder.build(kind: .oauth, scopes: ["gist"],
                                              probe: nil, expiresAt: expiry)
        let expected = "expires \(expiry.formatted(date: .abbreviated, time: .omitted))"
        XCTAssertEqual(result.details.last, expected)
        XCTAssertEqual(result.summary, "gists")
    }

    func testSummaryTruncatedAtWordBoundary() {
        let scopes = ["repo", "admin:org", "workflow", "delete_repo", "notifications"]
        let result = DescriptionBuilder.build(kind: .classic, scopes: scopes,
                                              probe: nil, expiresAt: nil)
        XCTAssertLessThanOrEqual(result.summary.count, 61)  // 60 + "…"
        XCTAssertTrue(result.summary.hasSuffix("…"))
        XCTAssertFalse(result.summary.contains("……"))
    }

    func testTruncateHelper() {
        XCTAssertEqual(DescriptionBuilder.truncate("short", to: 60), "short")
        XCTAssertEqual(DescriptionBuilder.truncate("one two three", to: 8), "one two…")
    }

    func testFineGrainedSummaryNamesRepos() {
        let probe = ProbeReport(repos: .granted(detail: ["api", "web", "infra", "docs", "ops"]),
                                orgs: .granted(detail: nil),
                                gists: .denied(needed: nil),
                                notifications: .unknown,
                                emails: .denied(needed: "email=read"))
        let result = DescriptionBuilder.build(kind: .fineGrained, scopes: nil,
                                              probe: probe, expiresAt: nil)
        XCTAssertEqual(result.summary, "repos: api, web (+3); orgs")
        XCTAssertEqual(result.details, [
            "repo access: api, web, infra, docs, ops",
            "org read access",
            "no gist access",
            "notifications access: probe failed",
            "no email access (needs: email=read)",
        ])
    }

    func testFineGrainedNothingGranted() {
        let probe = ProbeReport(repos: .denied(needed: nil), orgs: .denied(needed: nil),
                                gists: .denied(needed: nil), notifications: .denied(needed: nil),
                                emails: .denied(needed: nil))
        let result = DescriptionBuilder.build(kind: .fineGrained, scopes: nil,
                                              probe: probe, expiresAt: nil)
        XCTAssertEqual(result.summary, "no API read access found")
    }

    func testNoInputsYieldsEmpty() {
        let result = DescriptionBuilder.build(kind: .fineGrained, scopes: nil,
                                              probe: nil, expiresAt: nil)
        XCTAssertEqual(result.summary, "")
        XCTAssertEqual(result.details, [])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter DescriptionBuilderTests 2>&1 | tail -5`
Expected: compilation failure — `DescriptionBuilder` not defined.

- [ ] **Step 3: Implement DescriptionBuilder**

`Sources/GitHubTouchCore/DescriptionBuilder.swift`:

```swift
import Foundation

/// Turns what we know about a token (scopes or probe results) into the menu
/// one-liner and the capability details list. Pure — no I/O. This is the seam
/// where an LLM could plug in later; deliberately not done (spec).
public enum DescriptionBuilder {
    public static func build(kind: TokenKind, scopes: [String]?, probe: ProbeReport?,
                             expiresAt: Date?) -> (summary: String, details: [String]) {
        var summary = ""
        var details: [String] = []

        if let scopes, !scopes.isEmpty {
            let described = scopes.map { scope -> String in
                let (phrase, dangerous) = ScopeCatalog.describe(scope)
                return dangerous ? "⚠ \(phrase)" : phrase
            }
            summary = truncate(described.joined(separator: ", "), to: 60)
            details = described
        } else if let probe {
            var parts: [String] = []
            if case .granted(let names) = probe.repos {
                let names = names ?? []
                if names.isEmpty {
                    parts.append("repos")
                } else {
                    let shown = names.prefix(2).joined(separator: ", ")
                    let more = names.count > 2 ? " (+\(names.count - 2))" : ""
                    parts.append("repos: \(shown)\(more)")
                }
            }
            if case .granted = probe.orgs { parts.append("orgs") }
            if case .granted = probe.gists { parts.append("gists") }
            if case .granted = probe.notifications { parts.append("notifications") }
            if case .granted = probe.emails { parts.append("email") }
            summary = parts.isEmpty ? "no API read access found"
                                    : truncate(parts.joined(separator: "; "), to: 60)
            details = [
                detailLine(probe.repos, granted: { names in
                    "repo access: " + ((names?.isEmpty ?? true) ? "none visible" : names!.joined(separator: ", "))
                }, deniedName: "repo", unknownName: "repo"),
                detailLine(probe.orgs, granted: { _ in "org read access" },
                           deniedName: "org", unknownName: "org"),
                detailLine(probe.gists, granted: { _ in "gist read access" },
                           deniedName: "gist", unknownName: "gists"),
                detailLine(probe.notifications, granted: { _ in "notifications read access" },
                           deniedName: "notifications", unknownName: "notifications"),
                detailLine(probe.emails, granted: { _ in "email read access" },
                           deniedName: "email", unknownName: "email"),
            ]
        }

        if let expiresAt {
            details.append("expires \(expiresAt.formatted(date: .abbreviated, time: .omitted))")
        }
        return (summary, details)
    }

    private static func detailLine(_ outcome: ProbeOutcome,
                                   granted: ([String]?) -> String,
                                   deniedName: String, unknownName: String) -> String {
        switch outcome {
        case .granted(let detail):
            return granted(detail)
        case .denied(let needed):
            let suffix = needed.map { " (needs: \($0))" } ?? ""
            return "no \(deniedName) access\(suffix)"
        case .unknown:
            return "\(unknownName) access: probe failed"
        }
    }

    static func truncate(_ s: String, to limit: Int) -> String {
        guard s.count > limit else { return s }
        var head = String(s.prefix(limit))
        if let lastSpace = head.lastIndex(of: " ") {
            head = String(head[..<lastSpace])
        }
        while head.hasSuffix(",") || head.hasSuffix(";") { head.removeLast() }
        return head + "…"
    }
}
```

Note on the test expectations: `testFineGrainedSummaryNamesRepos` expects the gists detail line `"no gist access"` (deniedName "gist") and unknown notifications `"notifications access: probe failed"` — the deniedName/unknownName arguments above are chosen to produce exactly the strings in the tests. If a test string and the code disagree, the test is the contract; adjust the code.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test 2>&1 | grep -E "Executed .* tests" | tail -1`
Expected: `Executed 42 tests, with 0 failures`.

- [ ] **Step 5: Align the spec (drop the "write: as configured" clause)**

The spec's DescriptionBuilder section says the summary "appends 'write: as configured' only if the user recorded write permissions manually" — that couples the pure builder to UI-entered text for marginal value. YAGNI: the builder simply never asserts write capability. In `docs/superpowers/specs/2026-07-07-token-descriptions-design.md`, replace the sentence

> the summary never asserts write capability for fine-grained tokens — it reports reads as facts and appends "write: as configured" only if the user recorded write permissions manually.

with

> the summary never asserts write capability for fine-grained tokens — it reports probed reads as facts; anything about writes lives only in the user-editable permissions field.

- [ ] **Step 6: Commit**

```bash
git add Sources/GitHubTouchCore/DescriptionBuilder.swift Tests/GitHubTouchCoreTests/DescriptionBuilderTests.swift docs/superpowers/specs/2026-07-07-token-descriptions-design.md
git commit -m "feat: description builder turning scopes/probes into menu text"
```

---

### Task 4: TokenEntry.summary + AppState plumbing + menu display

**Files:**
- Modify: `Sources/GitHubTouchCore/TokenModels.swift`
- Modify: `Sources/GitHubTouch/AppState.swift` (addToken, updateMetadata, importCurrentToken)
- Modify: `Sources/GitHubTouch/MenuContentView.swift` (token row)
- Modify: `Sources/GitHubTouch/AddTokenView.swift` and `Sources/GitHubTouch/ManageView.swift` (ONLY the one-argument additions needed to keep the build green; the real UI work is Task 5)
- Test: `Tests/GitHubTouchCoreTests/VaultCryptoTests.swift` (add one backward-compat test)

**Interfaces:**
- Consumes: `DescriptionBuilder.build` (Task 3).
- Produces:
  - `TokenEntry.summary: String?` with init param `summary: String? = nil` (placed after `notes`); `TokenEntry.menuSummary: String` (`summary ?? permissionSummary`).
  - `AppState.addToken(label:kind:permissions:summary:expiresAt:notes:secret:) throws` — `summary: String?` added after `permissions`.
  - `AppState.updateMetadata(id:label:permissions:summary:notes:)` — `summary: String?` added after `permissions`.

- [ ] **Step 1: Write the failing backward-compat test**

Append to `Tests/GitHubTouchCoreTests/VaultCryptoTests.swift` inside the class:

```swift
    func testTokenEntryDecodesWithoutSummaryKey() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-000000000001","label":"old","kind":"classic",
         "permissions":["repo"],"createdAt":"2026-07-07T12:00:00Z","notes":"",
         "ephemeralPub":"","ciphertext":""}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entry = try decoder.decode(TokenEntry.self, from: Data(json.utf8))
        XCTAssertNil(entry.summary)
        XCTAssertEqual(entry.menuSummary, "repo")
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter testTokenEntryDecodesWithoutSummaryKey 2>&1 | tail -5`
Expected: compilation failure — `summary`/`menuSummary` not defined.

- [ ] **Step 3: Add the field and plumbing**

In `Sources/GitHubTouchCore/TokenModels.swift`:
- Add `public var summary: String?` after `public var notes: String`.
- Add init param `summary: String? = nil` after `notes: String`, and `self.summary = summary` in the body.
- Add after `permissionSummary`:

```swift
    /// What the menu row shows: the generated summary when present, else the
    /// raw permissions join.
    public var menuSummary: String {
        summary ?? permissionSummary
    }
```

(Synthesized Codable uses `decodeIfPresent` for optionals, so old vault files decode with `summary == nil` — that is what the Step 1 test proves.)

In `Sources/GitHubTouch/AppState.swift`:
- `addToken` signature becomes:

```swift
    func addToken(label: String, kind: TokenKind, permissions: [String], summary: String?,
                  expiresAt: Date?, notes: String, secret: String) throws {
```

  and the `TokenEntry(` call gains `summary: summary,` after `notes: notes,`.
- `updateMetadata` becomes:

```swift
    func updateMetadata(id: UUID, label: String, permissions: [String], summary: String?, notes: String) {
        guard var v = vault, let index = v.tokens.firstIndex(where: { $0.id == id }) else { return }
        v.tokens[index].label = label
        v.tokens[index].permissions = permissions
        v.tokens[index].summary = summary
        v.tokens[index].notes = notes
```

  (rest unchanged).
- In `importCurrentToken()`, replace the `let label = ...; try addToken(...)` block's addToken call with:

```swift
        let generated = DescriptionBuilder.build(kind: .oauth, scopes: info.scopes,
                                                 probe: nil, expiresAt: info.expiresAt)
        try addToken(label: label, kind: .oauth,
                     permissions: generated.details.isEmpty ? (info.scopes ?? []) : generated.details,
                     summary: generated.summary.isEmpty ? nil : generated.summary,
                     expiresAt: info.expiresAt,
                     notes: "imported from gh keychain on \(Date().formatted(date: .abbreviated, time: .omitted))",
                     secret: token)
```

In `Sources/GitHubTouch/MenuContentView.swift`, in `tokenRows`, change

```swift
                    Text("\(token.label)  (\(token.permissionSummary))")
```

to

```swift
                    Text("\(token.label)  (\(token.menuSummary))")
```

Keep the build green at the two existing call sites (full UI comes in Task 5):
- `Sources/GitHubTouch/AddTokenView.swift` `save()`: add `summary: nil,` after the `permissions:` argument.
- `Sources/GitHubTouch/ManageView.swift` Save Changes button: add `summary: token.summary,` after `permissions: permissions,`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift build 2>&1 | tail -3 && swift test 2>&1 | grep -E "Executed .* tests" | tail -1`
Expected: clean build, `Executed 43 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources Tests
git commit -m "feat: optional summary field on tokens, shown in the menu"
```

---

### Task 5: Generate in Add/Import UI + edit in Manage

**Files:**
- Modify: `Sources/GitHubTouch/AddTokenView.swift`
- Modify: `Sources/GitHubTouch/ManageView.swift`

**Interfaces:**
- Consumes: `DescriptionBuilder.build`, `CapabilityProber` (Tasks 2-3), `AppState.addToken`/`updateMetadata` with `summary:` (Task 4).
- Produces: final deliverable; nothing consumed later.

- [ ] **Step 1: AddTokenView — generate after validation**

Apply these changes to `Sources/GitHubTouch/AddTokenView.swift`:

1. Add state vars after `@State private var notes = ""`:

```swift
    @State private var summaryText = ""
    @State private var probing = false
```

2. In the `validate()` success path, replace

```swift
                validatedInfo = info
                validatedToken = token
                if let scopes = info.scopes {
                    permissionsText = scopes.joined(separator: ", ")
                }
```

with

```swift
                validatedInfo = info
                validatedToken = token
                if info.scopes != nil || kind != .fineGrained {
                    let generated = DescriptionBuilder.build(kind: kind, scopes: info.scopes,
                                                             probe: nil, expiresAt: info.expiresAt)
                    summaryText = generated.summary
                    permissionsText = generated.details.joined(separator: ", ")
                } else {
                    await runProbe(token: token, info: info)
                }
```

3. Add below `validate()`:

```swift
    /// Fine-grained tokens reveal nothing via headers; probe read access.
    @MainActor
    private func runProbe(token: String, info: TokenInfo) async {
        probing = true
        defer { probing = false }
        let report = try? await CapabilityProber().probe(token)
        guard token == pastedToken else { return }  // field changed mid-flight
        let generated = DescriptionBuilder.build(kind: .fineGrained, scopes: nil,
                                                 probe: report, expiresAt: info.expiresAt)
        summaryText = generated.summary
        permissionsText = generated.details.joined(separator: ", ")
    }
```

4. In the `Section("3 · Paste and validate")` body, replace the `if let info = validatedInfo` block's contents:

```swift
                if let info = validatedInfo {
                    Text("Valid for @\(info.login)"
                         + (info.expiresAt.map { ", expires \($0.formatted(date: .abbreviated, time: .omitted))" } ?? ""))
                        .foregroundStyle(.green)
                    if probing {
                        Text("Probing what this token can do…")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    TextField("Menu summary", text: $summaryText)
                    TextField("Permissions (comma-separated)", text: $permissionsText)
                    TextField("Notes", text: $notes)
                }
```

5. In `save()`, replace `summary: nil,` (added in Task 4) with:

```swift
                               summary: summaryText.trimmingCharacters(in: .whitespaces).isEmpty
                                   ? nil : summaryText.trimmingCharacters(in: .whitespaces),
```

6. In both `.onChange` handlers (pastedToken and kind), also reset the generated text:

```swift
            validatedInfo = nil
            validatedToken = nil
            summaryText = ""
```

- [ ] **Step 2: ManageView — editable summary**

Apply to `Sources/GitHubTouch/ManageView.swift` (`TokenRowEditor`):

1. Add state after `@State private var notes: String`:

```swift
    @State private var summaryText: String
```

and in `init`, after `_notes = ...`:

```swift
        _summaryText = State(initialValue: token.summary ?? "")
```

2. Extend `dirty`:

```swift
    private var dirty: Bool {
        label != token.label
            || permissionsText != token.permissions.joined(separator: ", ")
            || notes != token.notes
            || summaryText != (token.summary ?? "")
    }
```

3. Add a field between the label HStack and the Permissions TextField:

```swift
            TextField("Menu summary", text: $summaryText)
```

4. In the Save Changes action, replace `summary: token.summary,` (added in Task 4) with:

```swift
                    let trimmedSummary = summaryText.trimmingCharacters(in: .whitespaces)
                    state.updateMetadata(id: token.id, label: label,
                                         permissions: permissions,
                                         summary: trimmedSummary.isEmpty ? nil : trimmedSummary,
                                         notes: notes)
```

(adjusting the surrounding lines to keep it one call).

5. Bump the row height estimate in `ManageView`: change `* 130` to `* 150`.

- [ ] **Step 3: Verify build, tests, bundle**

Run: `swift build 2>&1 | tail -3 && swift test 2>&1 | grep -E "Executed .* tests" | tail -1 && ./build.sh 2>&1 | tail -2`
Expected: clean build (zero warnings), `Executed 43 tests, with 0 failures`, build.sh ends with the SE OK line + install message. Do NOT `open` the app.

Manual checks (deferred to human): add a real fine-grained token and watch the probe fill the summary; check the menu row shows the generated one-liner; edit the summary in Manage.

- [ ] **Step 4: Commit**

```bash
git add Sources
git commit -m "feat: auto-generate token descriptions in add/import, editable in manage"
```

---

## Self-review notes

- **Spec coverage:** ScopeCatalog table (T1) matches the spec's scope table; prober endpoints/timeout/concurrency/401-abort/X-Accepted header (T2); builder summary/details shapes incl. repo names, "+N", "no API read access found", 60-char word-boundary truncation, ⚠ prefixes, expiry line (T3); optional summary + decodeIfPresent compat test + menu fallback (T4); add-flow generation with probe progress line, import generation, Manage editing, probe-failure fallback (`try?` → report nil → empty summary, editable fields remain) (T5). "No LLM" honored; spec's "write: as configured" clause explicitly dropped with a spec edit (T3 Step 5).
- **Type consistency:** `ProbeOutcome.denied(needed:)` used identically in T2/T3; `build(kind:scopes:probe:expiresAt:)` identical in T3/T4/T5; `addToken`/`updateMetadata` summary param positions match between T4's definitions and T4/T5 call sites; `menuSummary` defined T4, used T4 (menu row).
- **Judgment calls:** import passes `generated.details` as permissions (falls back to raw scopes when empty); probe errors are non-fatal by `try?` in `runProbe`, matching spec's "probe failure is non-fatal".
