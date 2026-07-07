# GitHub Touch — Design

Date: 2026-07-07
Status: approved pending user review

## 1. What it is

A macOS menu bar app that holds multiple GitHub tokens encrypted under a
Secure Enclave key (Touch ID-gated, the same crypto proven in the sibling
project `../ssh-touch-add`). Picking a token from the menu triggers Touch ID,
decrypts only that token, and hands it to `gh auth login --with-token`, so it
lands in the macOS keychain where `gh` — and every tool that shells out to
`gh` — expects it. At midnight, or on demand, the app runs `gh auth logout`,
so no usable credential survives the day. The vault stores each token's
permissions and expiry as plaintext metadata, so the menu can always show
what each token can do.

Motivation: today a single non-expiring `gho_` OAuth token with broad scopes
(`repo`, `admin:org`, `gist`) sits permanently in the keychain. The goals are
least-privilege token selection per task, a guaranteed daily expiry of the
active credential, and not having to remember what any token is allowed to do.

Decisions made during brainstorming:

- Activation target: **keychain via `gh auth login --with-token`** (not
  hosts.yml, not env vars).
- Token kinds: **both fine-grained and classic PATs**, plus the captured
  legacy OAuth token.
- Interface: **menu bar app only** — no CLI.
- Existing broad token: **captured into the vault** as a "full access
  (legacy OAuth)" entry, then `gh` is logged out.
- Secret storage: **Secure Enclave vault file** (ssh-touch-add pattern), not
  native keychain items (their biometric ACLs bind to the code signature and
  make dev rebuilds painful).

## 2. Architecture

One SwiftUI app: SPM executable + `build.sh` producing `GitHub Touch.app`,
following the sibling project's build style. Requires macOS 13+ (for
`MenuBarExtra`). Three units:

### Vault (`Vault.swift`)

Lifted from `ssh-touch-add.swift`:

- One Secure-Enclave P-256 key-agreement key, access-controlled with
  `[.privateKeyUsage, .userPresence]` (Touch ID with account-password
  fallback), created on first save.
- Each token is sealed independently: fresh ephemeral P-256 ECDH against the
  SE public key, HKDF-SHA256 (salt = ephemeral public key, info =
  `"github-touch v1"`), AES-GCM. Decrypting token X performs one SE key
  agreement → one Touch ID prompt → only token X in memory.
- File: `~/Library/Application Support/github-touch/vault.json`, mode 600,
  written atomically. Ciphertexts plus plaintext metadata in one file.
- The SE key blob is not tied to the app's code signature; rebuilding the app
  does not require re-enrolling tokens.

### GhBridge (`GhBridge.swift`)

Wraps the `gh` CLI and the GitHub API:

- `activate(token)` → `gh auth login --hostname github.com --with-token`,
  token piped via stdin (never argv, never a temp file), then verified with
  `gh auth status`.
- `deactivate()` → `gh auth logout --hostname github.com`.
- `currentToken()` → `gh auth token` (used once, for the legacy import).
- `validate(token)` → `GET https://api.github.com/user` with the pasted
  token; on success reads response headers:
  - `X-OAuth-Scopes` → auto-fills permissions for classic/OAuth tokens;
  - `github-authentication-token-expiration` → auto-fills expiry when the
    token has one. Fine-grained permission lists are not reported by the
    API, so the user records those manually in the Add flow.
- Locates `gh` via `/opt/homebrew/bin/gh`, `/usr/local/bin/gh`, then PATH.

### UI (`MenuBarApp.swift` + sheets)

`MenuBarExtra` with:

- Header: active token label + "until 00:00", or "No token active".
- One row per vault token: label, permission summary, expiry; click →
  activate. Expired tokens greyed out with "expired".
- "Deactivate now", "Add token…", "Manage…", "Start at login" toggle
  (`SMAppService.mainApp`), "Quit".
- Sheets: **Add Token** (guided generation, section 5) and **Manage**
  (rename, edit permissions/notes, delete with confirmation). No plaintext
  reveal in v1.

## 3. Icons

Same production pipeline as the sibling project: hand-written SVG →
`qlmanage -t -s 1024` → `sips` size ladder → `iconutil -c icns`, scripted in
`icons/make-icns.sh`. Design candidates are kept as `a-*.svg`, `b-*.svg`, …
in `icons/` with the chosen one referenced by the build script.

**App icon** — theme: "the fingerprint is the key". Primary candidate: a
macOS-style rounded-square tile, dark background, showing a key whose round
bow is drawn as a fingerprint whorl, in a warm accent color against the dark
tile (visually related to ssh-touch-add's "Prompt" icon so the pair reads as
a family, but clearly distinct). 2–3 candidate SVGs will be sketched and the
best picked, keeping rejects in `icons/` per house style. No Octocat — it is
trademarked.

**Menu bar icon** — a template image (monochrome, so macOS adapts it to
light/dark menu bars and tinting), drawn from the same fingerprint-key mark
reduced to a 18×18pt glyph. Two states:

- **Active**: filled glyph at full opacity, with a small solid dot badge at
  the lower right (reads as "loaded" at a glance).
- **Inactive**: outline variant at reduced opacity (no badge).

Rendered as template PNGs (@1x/@2x) from the same SVG source in
`make-icns.sh`. Fallback if the custom glyph reads poorly at 18pt: the SF
Symbol `touchid` with the same active/inactive treatment.

## 4. Data model

`vault.json`:

```json
{
  "version": 1,
  "seKey": "<Secure Enclave private key blob, base64>",
  "tokens": [
    {
      "id": "UUID",
      "label": "repo read-only",
      "kind": "fineGrained | classic | oauth",
      "permissions": ["contents: read", "metadata: read"],
      "expiresAt": "2026-10-01T00:00:00Z | null",
      "createdAt": "2026-07-07T12:00:00Z",
      "lastActivatedAt": "2026-07-07T12:00:00Z | null",
      "notes": "for CI debugging tools",
      "ephemeralPub": "<base64>",
      "ciphertext": "<base64 AES-GCM combined box>"
    }
  ]
}
```

Activation state lives in UserDefaults: `activeTokenId` and `clearAt`
(next-midnight timestamp computed at activation). This lets a relaunched app
detect an overdue clear without touching the vault.

## 5. Flows

### Activate

Menu → click a token → Touch ID (SE key agreement) → decrypt → pipe to
`gh auth login` → verify via `gh auth status` → set `activeTokenId`/`clearAt`
→ icon lights up → notification "«label» active until 00:00". Activating
while another token is active simply replaces it (gh login overwrites).

### Clear (the point of the app)

`gh auth logout` runs when any of these first notices `now >= clearAt`:

1. a scheduled timer firing at midnight while the app runs;
2. `NSWorkspace.didWakeNotification` (Mac slept through midnight);
3. app launch (app wasn't running at midnight).

Manual "Deactivate now" does the same immediately. After logout, verify with
`gh auth status` (expect "not logged in") and clear
`activeTokenId`/`clearAt`.

### Add token (guided generation)

GitHub has no API for creating PATs, so generation is browser-guided:

1. Sheet asks: kind (fine-grained / classic), label, intended purpose.
2. **Classic**: opens
   `https://github.com/settings/tokens/new?scopes=<picked>&description=<label>`
   pre-filled from checkboxes in the sheet.
   **Fine-grained**: opens
   `https://github.com/settings/personal-access-tokens/new` (that page
   ignores most URL prefills) and the sheet shows a checklist of what to
   select, mirroring the user's stated purpose.
3. User generates on github.com and pastes the token into the sheet.
4. App validates via `GET /user`; on success auto-fills scopes (classic) and
   expiry (header) where available; user confirms/edits label, permissions
   list, notes.
5. Token is sealed into the vault. Nothing is stored if validation fails.

### Import existing token (first run)

If the vault is empty and `gh auth status` shows a logged-in keychain token:
offer to capture it — `gh auth token` → validate → store as "full access
(legacy OAuth)" with scopes from `X-OAuth-Scopes` → `gh auth logout`. The
big hammer remains available, but only behind Touch ID.

### Manage

Rename, edit permissions/notes (metadata only — no re-encryption needed),
delete with confirmation dialog.

## 6. Errors and edge cases

- `gh` not installed → menu body replaced by a hint ("brew install gh").
- Touch ID cancelled → no-op, no error surfaced.
- `gh auth login`/`logout` failure → notification with stderr summary; the
  menu icon always reflects actual `gh auth status`, never assumed state.
- Vault unreadable/corrupt → dialog offering to reset the vault (tokens are
  regenerable on github.com; nothing else is lost).
- Pasted token invalid (401) → inline error in the Add sheet, nothing saved.
- Expired token clicked → prompt to replace it via the Add flow.
- Clock changes/timezone: `clearAt` is recomputed from `Calendar.current` at
  activation; the launch/wake checks compare against wall-clock now.

## 7. Security properties

- Plaintext token exists only in app memory between Touch ID and the stdin
  pipe to `gh`; never on argv, never in a file, never in the pasteboard.
- Metadata (labels, permission names, expiry) is deliberately unencrypted —
  permission names are not secrets, and the menu must render them without
  prompting.
- The vault is useless off this Mac: the SE private key never leaves the
  Secure Enclave.
- Honest caveat (goes in the README): while a token is active — until
  midnight — it sits in the keychain exactly as exposed as the current
  permanent setup. The win is least-privilege scoping plus guaranteed daily
  expiry, not runtime protection of the active token.

## 8. Testing

- **Vault**: automated round-trip test of the SE plumbing using a key
  without `.userPresence` (the sibling's `--test-plumbing` trick), run as an
  XCTest/`swift test` target: seal N tokens, unseal each, verify isolation.
- **GhBridge**: tests against a fake `gh` shell script placed first on PATH
  (records argv, asserts token arrived via stdin); one manual end-to-end
  pass with a real throwaway token.
- **UI/lifecycle**: manual checklist in the README — activate, deactivate,
  relaunch-past-deadline clears, wake-past-deadline clears — helped by a
  debug-build-only "Clear in 1 minute" menu item.

## 9. Out of scope (v1)

- Multiple GitHub accounts or GHE hosts (single `github.com` / `dvrensk`).
- Revoking tokens on GitHub's side (manual, via settings page).
- Countdown display in the menu bar.
- Custom activation durations shorter than midnight.
- Notarization / distribution beyond this machine.
