# Colour Tags, Default Token, Timed Activation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tokens get green/orange/red tags that colour the menu bar icon, one token can be the default that `gh` falls back to when a timed activation ends, and every non-default activation lasts for a chosen Duration (15 min / 30 min / 1 hour / Until midnight) with a visible countdown and Extend.

**Architecture:** Pure, unit-tested pieces in GitHubTouchCore (`TokenTag`, optional `tag`/`defaultTokenId` fields, `ActivationDuration`, `ActivationState.untilMidnight` + `extended`/`reconciled`/`countdownText`, and a `deadlineAction` decision function). AppState holds the default's plaintext in memory after a one-touch double unseal and acts on `deadlineAction` at the deadline. SwiftUI views gain the tag picker, default toggle, Duration submenu, Extend, coloured dots, and a tinted menu bar icon with a countdown.

**Tech Stack:** Swift 5.10, SwiftUI `MenuBarExtra` (menu style), CryptoKit Secure Enclave, LocalAuthentication, XCTest.

**Spec:** `docs/superpowers/specs/2026-10-23-tags-default-timed-design.md`
**Branch:** `feature/tags-default-timed`, cut from `main`. Suite is green on `main` before starting (`swift test`).

## Global Constraints

- macOS 13 floor, swift-tools 5.10, no third-party dependencies.
- Token secrets live in memory only: never on disk, argv, logs, pasteboard or notification text. The held default secret is a non-published AppState property, dropped as soon as it is used or the default changes.
- `vault.json` stays version 1. New fields are optionals that decode from files lacking them; UserDefaults keys that are missing load as today's behaviour.
- Tag colours: system green, orange, red (`NSColor.systemGreen/systemOrange/systemRed`, SwiftUI `.green/.orange/.red`).
- Duration options, in order, with these menu titles: `15 min`, `30 min`, `1 hour`, `Until midnight`. Default when unset: `Until midnight`.
- Switching back to the default never prompts for Touch ID. If it can't be done silently, log out.
- No tag, no default set ⇒ behaviour identical to today apart from Duration.
- Commit after every task, message ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Mac asleep through the deadline.** On wake the switch to the default happens with no prompt (memory survives sleep) — pinned by the deadline-decision tests (Task 4) plus manual check 4 in Task 9.
2. **Marking the currently active token as default, or un-marking it.** A just-made default must lose its timer; an ex-default that is still active must get an Until-midnight timer instead of staying on forever — `testReconciled…` tests in Task 3.
3. **Existing installs.** An old `vault.json` (no `tag`, no `defaultTokenId`) and old UserDefaults (no `untilMidnight`, no `activationDuration`) load unchanged — decoding tests in Tasks 2 and 3.
4. **Repeated Extend.** Pressing Add 15 min twice adds 30 min to the original deadline (from `clearAt`, not from now); Keep Until Midnight sets the flag — `testExtended…` tests in Task 3.
5. **Default changed, cleared, deleted or expired while a timer runs.** Must log out rather than restore a stale or expired token — `testDeadlineAction…` tests in Task 4.

---

### Task 1: Branch, docs, and the one-touch spike

The spec makes this a gate: prove one Touch ID prompt can unseal two vault entries before building on it.

**Files:**
- Modify: `Sources/GitHubTouch/Main.swift`
- Possibly modify: `Sources/GitHubTouchCore/VaultCrypto.swift` (`SecureEnclaveVaultKey.load`)

**Interfaces:**
- Produces: `SecureEnclaveVaultKey.load(blob:reason:)` guaranteed to authenticate once for any number of `sharedSecret` calls on the returned key. Signature stays `throws -> SecureEnclave.P256.KeyAgreement.PrivateKey` (synchronous) unless Step 4 forces a change; if it does, record the new signature in the commit message and Task 5 uses that.

- [ ] **Step 1: Branch and commit the spec and this plan**

```bash
git switch -c feature/tags-default-timed
git add docs/superpowers/specs/2026-10-23-tags-default-timed-design.md docs/superpowers/plans/2026-10-23-tags-default-timed.md
git commit -m "docs: spec and plan for colour tags, default token, timed activation"
```

- [ ] **Step 2: Add a `--test-one-touch` flag to `Main.swift`**

`static func testOneTouch() -> Never`, dispatched like `--test-plumbing`: create a key with `SecureEnclaveVaultKey.create(requireUserPresence: true)`, seal `"secret-one"` and `"secret-two"`, load it back with `SecureEnclaveVaultKey.load(blob: key.dataRepresentation, reason: "one-touch self-test")`, unseal both, print `OK: unsealed 2 secrets` (or `FAIL: …`), exit 0/1.

- [ ] **Step 3: Run it and count prompts**

Run: `swift build && .build/debug/GitHubTouch --test-one-touch` — a human must touch the sensor. Ask David to run it if you can't.
Expected: exactly one Touch ID prompt, then `OK: unsealed 2 secrets`. If the bare binary can't reach the Secure Enclave, run `./build.sh` and use `"./GitHub Touch.app/Contents/MacOS/GitHubTouch" --test-one-touch` instead.

- [ ] **Step 4: Only if there were two prompts — pre-evaluate the context**

In `SecureEnclaveVaultKey.load`, evaluate the `LAContext` with `.deviceOwnerAuthentication` and the reason *before* constructing the key, then pass that context. Keep the method synchronous (block on the evaluation with a semaphore; callers already run it in `Task.detached`). `LAError.userCancel`/`.appCancel` must still propagate as thrown `LAError` so AppState's silent-cancel catch keeps working. Re-run Step 3: one prompt. If that still prompts twice, try `touchIDAuthenticationAllowableReuseDuration = 10` on the context; if nothing works, keep two prompts (spec's accepted fallback) and say so in the commit.

- [ ] **Step 5: Commit**

```bash
git add Sources/GitHubTouch/Main.swift Sources/GitHubTouchCore/VaultCrypto.swift
git commit -m "feat: one-touch self-test proving a single prompt unseals two entries"
```

---

### Task 2: Tags and default in the vault model

**Files:**
- Modify: `Sources/GitHubTouchCore/TokenModels.swift`
- Test: `Tests/GitHubTouchCoreTests/VaultStoreTests.swift`

**Interfaces:**
- Produces:
  - `public enum TokenTag: String, Codable, CaseIterable, Sendable { case green, orange, red }`
  - `TokenEntry.tag: TokenTag?`, init gains trailing `tag: TokenTag? = nil`
  - `VaultFile.defaultTokenId: UUID?`, init gains trailing `defaultTokenId: UUID? = nil`

- [ ] **Step 1: Write the failing tests** in `VaultStoreTests`

- `testTagAndDefaultRoundTrip`: save a vault with one `TokenEntry` tagged `.red` and `defaultTokenId` = that entry's id; load; `XCTAssertEqual(back.tokens[0].tag, .red)`, `XCTAssertEqual(back.defaultTokenId, id)`.
- `testLegacyVaultWithoutTagOrDefaultDecodes`: write this JSON to `vaultURL` and load it; assert `tokens[0].tag == nil`, `defaultTokenId == nil`, `tokens[0].label == "old"`.

```json
{"version":1,"seKey":"AQ==","sePub":"Ag==","tokens":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","label":"old","kind":"classic","permissions":[],"createdAt":"2026-07-07T10:00:00Z","notes":"","ephemeralPub":"Aw==","ciphertext":"BA=="}]}
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter VaultStoreTests`
Expected: compile failure — `tag` / `defaultTokenId` not members.

- [ ] **Step 3: Add the type and fields** as in Interfaces. Synthesized `Codable` already uses `decodeIfPresent` for optionals; no custom coding.

- [ ] **Step 4: Run all tests**

Run: `swift test`
Expected: all pass (existing call sites compile thanks to the defaulted init parameters).

- [ ] **Step 5: Commit** — `feat: colour tag and default-token fields in the vault`

---

### Task 3: Duration and activation-state rules

**Files:**
- Modify: `Sources/GitHubTouchCore/ActivationState.swift`
- Test: `Tests/GitHubTouchCoreTests/ActivationStateTests.swift`

**Interfaces:**
- Consumes: `nextMidnight(after:calendar:)` (existing).
- Produces:
  - `public enum ActivationDuration: String, CaseIterable, Codable, Sendable { case fifteenMinutes, thirtyMinutes, oneHour, untilMidnight }`
    - `var menuTitle: String` — the four titles in Global Constraints.
    - `var minutes: Int?` — 15 / 30 / 60 / nil.
    - `func clearAt(from now: Date, calendar: Calendar = .current) -> Date` — `now + minutes`, or `nextMidnight(after: now)`.
  - `ActivationState.untilMidnight: Bool` (init gains `untilMidnight: Bool = false`; stays `Equatable`).
  - `func extended(by duration: ActivationDuration, calendar: Calendar = .current) -> ActivationState` — finite: `clearAt += minutes`, `untilMidnight` unchanged; `.untilMidnight`: `clearAt = nextMidnight(after: clearAt ?? now)`, `untilMidnight = true`. No-op when `clearAt == nil`.
  - `func reconciled(withDefault defaultId: UUID?, now: Date = Date(), calendar: Calendar = .current) -> ActivationState` — active id == defaultId ⇒ `clearAt = nil, untilMidnight = false`; active, not the default, `clearAt == nil` ⇒ `clearAt = nextMidnight(after: now)`, `untilMidnight = true`; otherwise unchanged.
  - `func countdownText(now: Date = Date()) -> String?` — nil when inactive, `clearAt == nil`, or `untilMidnight`; else remaining ≥ 60 s ⇒ `"\(Int(ceil(remaining / 60)))m"`, 0 < remaining < 60 ⇒ `"<1m"`, remaining ≤ 0 ⇒ nil.
  - `ActivationStateStore`: persists `untilMidnight` under key `"untilMidnight"` (missing ⇒ false); `func loadDuration() -> ActivationDuration` (key `"activationDuration"`, missing/unknown ⇒ `.untilMidnight`) and `func saveDuration(_:)`.

- [ ] **Step 1: Write the failing tests** (use the Europe/Madrid calendar pattern already in the file; `t0 = 2026-07-07T15:30:00+02:00`)

- `testDurationClearAt`: `.fifteenMinutes.clearAt(from: t0)` = t0+900; `.oneHour` = t0+3600; `.untilMidnight` = `2026-07-08T00:00:00+02:00`.
- `testDurationMenuTitlesInOrder`: `ActivationDuration.allCases.map(\.menuTitle) == ["15 min", "30 min", "1 hour", "Until midnight"]`.
- `testExtendedAddsFromClearAtNotNow`: state clearAt = t0+600; `.extended(by: .fifteenMinutes).extended(by: .fifteenMinutes).clearAt` = t0+600+1800.
- `testExtendedUntilMidnightSetsFlag`: from clearAt t0+600 → clearAt next midnight, `untilMidnight == true`.
- `testExtendedNoOpWithoutClearAt`: `ActivationState(activeTokenId: id).extended(by: .thirtyMinutes)` equals itself.
- `testReconciledMakesNewDefaultTimerless`: active id X, clearAt t0+600, reconciled(withDefault: X) ⇒ clearAt nil, untilMidnight false.
- `testReconciledGivesExDefaultAMidnightTimer`: active X, clearAt nil, reconciled(withDefault: nil, now: t0) ⇒ clearAt next midnight, untilMidnight true. Same with a different default id Y.
- `testReconciledLeavesTimedNonDefaultAlone` and inactive state unchanged.
- `testCountdownText`: clearAt now+23*60+10 ⇒ `"24m"`; now+30 ⇒ `"<1m"`; now-1 ⇒ nil; untilMidnight ⇒ nil; clearAt nil ⇒ nil.
- `testStoreRoundTripsUntilMidnightAndDuration`: extend `testStoreRoundTrip` style with a fresh suite: save state with `untilMidnight: true` ⇒ loads equal; `loadDuration()` on empty defaults == `.untilMidnight`; `saveDuration(.thirtyMinutes)` ⇒ `loadDuration() == .thirtyMinutes`.

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter ActivationStateTests`
Expected: compile failure on the new names.

- [ ] **Step 3: Implement** the Interfaces block in `ActivationState.swift`.

- [ ] **Step 4: Run all tests** — `swift test`, all pass.

- [ ] **Step 5: Commit** — `feat: activation durations, extend, default reconciliation, countdown text`

---

### Task 4: What happens at the deadline

**Files:**
- Create: `Sources/GitHubTouchCore/DeadlineAction.swift`
- Test: `Tests/GitHubTouchCoreTests/DeadlineActionTests.swift`

**Interfaces:**
- Produces:

```swift
public enum LogoutReason: Equatable, Sendable { case noDefault, defaultNotHeld, defaultChanged, defaultExpired }
public enum DeadlineAction: Equatable, Sendable { case switchToDefault(UUID), logout(LogoutReason) }
public func deadlineAction(defaultTokenId: UUID?, heldDefaultId: UUID?, defaultExpired: Bool) -> DeadlineAction
```

Checked in this order: no default ⇒ `.noDefault`; nothing held ⇒ `.defaultNotHeld`; held id ≠ default id ⇒ `.defaultChanged`; `defaultExpired` ⇒ `.defaultExpired`; else `.switchToDefault(defaultTokenId)`.

- [ ] **Step 1: Write the failing tests** — one per row above (`testDeadlineActionNoDefault`, `…NotHeld`, `…Changed`, `…Expired`, `…SwitchesToDefault`), plus `testDeadlineActionNoDefaultWinsOverHeld` (held id present, default nil ⇒ `.logout(.noDefault)`).

- [ ] **Step 2: Run** — `swift test --filter DeadlineActionTests`, compile failure.

- [ ] **Step 3: Implement** in `DeadlineAction.swift`.

- [ ] **Step 4: Run** — `swift test`, all pass.

- [ ] **Step 5: Commit** — `feat: deadline decision — switch to the held default or log out`

---

### Task 5: AppState — timed activation, held default, switch back

No unit tests exist for the app target; this task is verified by `swift build` and the manual checks in Task 9. Keep the logic thin — the decisions live in Tasks 3–4.

**Files:**
- Modify: `Sources/GitHubTouch/AppState.swift`

**Interfaces:**
- Consumes: everything from Tasks 1–4.
- Produces (used by Tasks 6–8):
  - `@Published var duration: ActivationDuration` (loaded via `stateStore.loadDuration()`, `didSet` saves)
  - `@Published var now: Date` — refreshed every 30 s by a `.common`-mode Timer started in `init`
  - `var defaultTokenId: UUID?` (from `vault`), `var defaultToken: TokenEntry?`
  - `var canSwitchToDefault: Bool` — a held default exists, a token is active, and it isn't the default
  - `func activate(_ entry: TokenEntry)` (changed)
  - `func extend()`, `func switchToDefaultNow()`
  - `func setTag(id: UUID, tag: TokenTag?)`, `func setDefault(id: UUID?)`
  - private `struct HeldDefault { let id: UUID; let secret: String }`, `private var heldDefault: HeldDefault?` — **not** `@Published`.

- [ ] **Step 1: `activate(_:)`**

Inside the existing detached task, after loading the key once: unseal `entry`; additionally unseal the default (with `try?`) when the entry is not the default, a default exists, it isn't expired, and `heldDefault?.id != defaultTokenId`. Then `gh.activate`. On success:
- entry is the default ⇒ `ActivationState(activeTokenId: id)` (no clearAt), invalidate `clearTimer`, `heldDefault = nil`, notify `“<label>” active (default).`
- otherwise ⇒ `clearAt = duration.clearAt(from: Date())`, `untilMidnight: duration == .untilMidnight`, store any freshly unsealed default in `heldDefault`, `scheduleClear(at:)`, notify `“<label>” active until midnight.` or `“<label>” active until 14:32.` (`clearAt.formatted(date: .omitted, time: .shortened)`).
Keep `markActivated`, `ghLoggedIn = true`, and the silent-cancel catch.

- [ ] **Step 2: Deadline handling**

`checkDeadline()` calls a new `handleDeadline()` instead of `deactivate()` when overdue. `handleDeadline()` captures the expiring token's label, then switches on `deadlineAction(defaultTokenId:heldDefaultId:defaultExpired:)`:
- `.switchToDefault` ⇒ `gh.activate(token: held.secret)` detached; success ⇒ state = default active with no timer, save, `heldDefault = nil`, `markActivated`, notify `Back to “<default label>” (default).`; failure ⇒ `deactivate()` (its existing retry path covers an overdue clear).
- `.logout(.noDefault)` ⇒ `deactivate()` (today's “GitHub token cleared.”).
- `.logout(.defaultNotHeld)` / `.defaultChanged` ⇒ `deactivate(silent: true)` + notify `“<label>” cleared. Pick the default in the menu to restore it.`
- `.logout(.defaultExpired)` ⇒ `deactivate(silent: true)` + notify `“<label>” cleared. The default “<default label>” has expired.`
`deactivate` also sets `heldDefault = nil`. Guard against re-entry while a switch is in flight (a `private var handlingDeadline = false`), since wake and the timer can both fire.

- [ ] **Step 3: `extend()`, `switchToDefaultNow()`**

`extend()` ⇒ `activation = activation.extended(by: duration)`, save, `scheduleClear(at: activation.clearAt!)`. `switchToDefaultNow()` ⇒ the same code path as `.switchToDefault` in Step 2 (factor it into one private method).

- [ ] **Step 4: `setTag`, `setDefault`, delete, launch**

`setTag`/`setDefault` save the vault the way `updateMetadata` does. `setDefault` then sets `activation = activation.reconciled(withDefault: id)`, saves it, reschedules or invalidates `clearTimer` to match `activation.clearAt`, and drops `heldDefault` when its id ≠ the new default. `deleteToken` clears `defaultTokenId` when deleting the default. In `init`, apply `.reconciled(withDefault: vault?.defaultTokenId)` to the loaded activation before `checkDeadline()`. `resetVault` also clears `heldDefault`.

- [ ] **Step 5: Build** — `swift build`, no errors or new warnings; `swift test` still green.

- [ ] **Step 6: Commit** — `feat: timed activation with one-touch default fallback`

---

### Task 6: Manage Tokens — tag picker and default toggle

**Files:**
- Create: `Sources/GitHubTouch/TokenTag+Color.swift`
- Modify: `Sources/GitHubTouch/ManageView.swift`

**Interfaces:**
- Consumes: `state.setTag`, `state.setDefault`, `state.defaultTokenId`.
- Produces: `extension TokenTag { var color: Color; var nsColor: NSColor; var displayName: String }` (`"Green"`, `"Orange"`, `"Red"`) — used by Tasks 7–8.

- [ ] **Step 1: Add `TokenTag+Color.swift`** per Interfaces, colours per Global Constraints.

- [ ] **Step 2: Extend `TokenRowEditor`**

Under the label row add an `HStack`: a segmented `Picker("Tag", selection:)` over `TokenTag?` with `None` + the three tags (each option shows a filled circle in its colour plus the name), and a `Toggle("Default", isOn:)` bound to `state.defaultTokenId == token.id` whose setter calls `state.setDefault(id: on ? token.id : nil)`. Both apply immediately (not via Save Changes) — they are one-click choices. Grow the per-row height in `ManageView`'s frame formula from 150 to 180.

- [ ] **Step 3: Build and look** — `swift build && .build/debug/GitHubTouch`; open Manage Tokens, set a tag and a default on two tokens, reopen the window: values persisted, only one token shows Default on.

- [ ] **Step 4: Commit** — `feat: tag picker and default toggle in Manage Tokens`

---

### Task 7: Menu — dots, default label, header, Duration, Extend

**Files:**
- Modify: `Sources/GitHubTouch/MenuContentView.swift`

**Interfaces:**
- Consumes: Task 5's AppState API; Task 6's `TokenTag.nsColor`; Task 3's `countdownText`.

- [ ] **Step 1: Token rows**

Prefix tagged rows with a coloured dot. Use a non-template `NSImage` (a filled 8 pt circle drawn in `tag.nsColor`, `isTemplate = false`) via `Image(nsImage:)`, because SwiftUI menus render SF Symbols monochrome; untagged rows get no dot. Append ` — default` to the default token's row text. Keep today's disabled rules.

- [ ] **Step 2: Header**

- default active ⇒ `Active: <label> (default)`
- timed, untilMidnight ⇒ `Active: <label> — until midnight`
- timed, finite ⇒ `Active: <label> — <N> min left (until 14:32)`, N = ceil(remaining/60), computed from `state.now`
- none ⇒ `No token active`

- [ ] **Step 3: Actions section** (between the token rows and Add Token…)

- `Add <duration.menuTitle>` (finite Duration) or `Keep Until Midnight` (Duration = Until midnight) ⇒ `state.extend()`. Shown only when the active token has a clearAt and it is not the case that both `activation.untilMidnight` and `duration == .untilMidnight`.
- `Switch to Default Now` when `state.canSwitchToDefault`.
- `Deactivate Now` as today.
- `Picker("Duration", selection: $state.duration)` over `ActivationDuration.allCases` labelled by `menuTitle`, `.pickerStyle(.menu)` so it renders as a submenu with a checkmark.

- [ ] **Step 4: Debug item** — make `Debug: Clear in 1 Minute` set clearAt via the same state + `scheduleClear` it does today (so it exercises `handleDeadline`); no other change.

- [ ] **Step 5: Build and look** — `swift build && .build/debug/GitHubTouch`; open the menu: dots, `— default`, Duration submenu with one checkmark that sticks after relaunch.

- [ ] **Step 6: Commit** — `feat: menu shows tags, default, countdown, duration and extend`

---

### Task 8: Menu bar icon — tag colour and countdown

**Files:**
- Modify: `Sources/GitHubTouch/GitHubTouchApp.swift` (`MenuBarIcon`)

**Interfaces:**
- Consumes: `state.activeToken?.tag`, `state.activation.countdownText(now: state.now)`, `TokenTag.nsColor`.

- [ ] **Step 1: Change `MenuBarIcon`** to take `tag: TokenTag?` and `countdown: String?` alongside `active`. Inactive, or active and untagged ⇒ exactly today's template rendering. Active and tagged ⇒ a non-template copy of the template PNG tinted with `tag.nsColor` (draw the image, then fill its bounds with the colour using `.sourceAtop`), full opacity. The dev fallback (`touchid` SF Symbol) uses `.foregroundStyle(tag.color)`. When `countdown` is non-nil, show it as `Text` after the image in an `HStack`. Pass the new values from `GitHubTouchApp`.

- [ ] **Step 2: Build and look** — `./build.sh` (rebuilds and installs to `~/Applications`), launch the installed app, activate a tagged token with Duration 15 min: icon in the tag colour with `15m` beside it, ticking down within 30 s; activate an untagged token: plain icon.

- [ ] **Step 3: Commit** — `feat: menu bar icon takes the active token's colour and shows time left`

---

### Task 9: README and the manual checklist

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update README** — in the intro and "How it works", replace "until midnight" as the only lifetime with: tokens activate for the chosen Duration; a default token (if set) takes over when the time runs out and stays on; one touch unlocks both, and the default is held only in memory; a relaunch mid-timer means logout at the deadline. Update "Honest caveat" to say the default stays in `gh`'s keychain indefinitely. Add tags to the feature description.

- [ ] **Step 2: Extend the manual test checklist** with:
  1. Tag a token in Manage; activate it; the icon takes its colour; untagged ⇒ plain icon.
  2. Set a default (green). Duration 15 min. Activate a red token: **one** Touch ID prompt; icon red with `15m`.
  3. Add 15 min ⇒ header shows ~30 min left.
  4. Debug "Clear in 1 Minute" ⇒ after a minute, `gh auth status` shows the default, icon green, no prompt, notification "Back to …". Repeat with the Mac asleep over the deadline.
  5. Activate a timed token, quit and relaunch, Debug "Clear in 1 Minute" ⇒ logs out with the "Pick the default in the menu" notification.
  6. While a timed token runs, change the default to another token ⇒ at the deadline it logs out (no stale restore).
  7. No default set ⇒ deadline logs out as before.

- [ ] **Step 3: Run the checklist** on the installed build (needs David at the sensor for Touch ID) and `swift test` once more. Note any failures in the branch summary rather than marking them done.

- [ ] **Step 4: Commit** — `docs: README for tags, default token and timed activation`
