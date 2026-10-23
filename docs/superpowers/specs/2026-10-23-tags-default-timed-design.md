# GitHub Touch — Colour Tags, Default Token, Timed Activation

Date: 2026-10-23
Status: draft, pending user review
Extends: 2026-07-07-github-touch-design.md, 2026-07-07-token-descriptions-design.md

## Why

Most of the day David wants a read-only token live in `gh`. Now and then an
agent needs write access for a maintenance job, and that access should last
for the job, not for the rest of the day. Today every activation lasts until
midnight and then `gh` is logged out entirely, so there is no "safe resting
state" and no short-lived "hot" access. He also wants to see at a glance, in
the menu bar, how dangerous the token that is live right now is.

## Goals

1. **Colour tags.** Each token can be tagged green, orange or red (or left
   untagged). The tags mean whatever David wants; the intended reading is
   green = read-only, orange = mixed, red = dangerous. The app never assigns
   or infers a tag.
2. **Menu bar icon in the active token's colour.** No token active: the icon
   stays as today (dimmed template). Active token with a tag: icon drawn in
   that colour. Active token without a tag: icon as today's active state.
3. **Default token.** One token can be marked as the default. Whenever a
   timed activation ends, the app switches `gh` back to the default instead
   of logging out. The default itself has no timer — it stays live until
   something else replaces it.
4. **Timed activation.** A Duration setting — 15 min, 30 min, 1 hour, Until
   midnight — applies to every activation of a non-default token. The menu
   shows how long is left and offers to extend.

## Non-goals

- No modifier-key (Alt-click) behaviour. The Duration setting replaces it.
- No automatic tagging from scopes/permissions.
- No auto-activation of the default at launch, login or after reboot (David
  rarely reboots; "whatever is easiest"). After a relaunch with nothing
  active, the default is one click away in the menu.
- No new at-rest copy of any token. The Touch ID vault stays the only place
  tokens live on disk (besides whatever `gh` holds while active, as today).

## Anti-goals

- Switching back to the default must never require a touch. If it can't be
  done silently, the app logs out instead — it must not leave the hot token
  live past its deadline while waiting for a touch.
- Untagged tokens and a vault with no default must behave exactly as today
  (except that Duration applies).

## Behaviour

### Tags

- Stored per token in the vault metadata (plaintext, like label/notes).
- Set in Manage Tokens with a small picker: None / Green / Orange / Red.
- Menu rows show a coloured dot before the label for tagged tokens.
- Colours: system green, orange, red.

### Default token

- Set in Manage Tokens ("Default" toggle / radio per row; at most one).
  Stored in the vault file. Deleting the default token clears the setting.
- Menu: the default row is labelled, e.g. `● read-only  (…summary…) — default`.
  *(Exact wording is the builder's call.)*
- Activating the default from the menu: one touch, goes live with **no
  timer** (clearAt = nil). Duration does not apply.
- Any tag, including red, may be the default. *(Builder's call: no restriction.)*

### One touch unlocks both (decided)

When David activates a non-default token and a default is set:

- The single Touch ID prompt unlocks both the chosen token and the default.
  Implementation: load the Secure Enclave key once with one `LAContext`
  and unseal both entries with it.
- The chosen token goes live in `gh` with its timer. The default's plaintext
  is kept **in memory only**, in AppState, until the timer runs out, then
  dropped.
- If the default is already in memory (a timed token is already running),
  only the new token needs unsealing.
- The in-memory copy is stored together with its token id. At expiry it is
  used only if that id still equals `defaultTokenId`; if the default was
  changed, cleared or deleted while the timer ran, the app logs out instead.
  *(Claude's call: never restore a token that is no longer the default.)*

**Risk to verify first:** that a second `sharedSecretFromKeyAgreement` on
the same loaded SE key does not prompt again. If it does, evaluate the
`LAContext` explicitly (`evaluatePolicy(.deviceOwnerAuthentication…)`) before
loading the key and pass that context, or set a reuse duration. Spike this
before building the rest. If neither works, two touches at activation is an
acceptable fallback — the switch back at expiry still needs none.

### Duration setting

- Menu submenu "Duration" with 15 min / 30 min / 1 hour / Until midnight,
  checkmark on the current choice. Persisted in UserDefaults.
  *(Builder's call: default value Until midnight, matching today.)*
- Applies at activation time: clearAt = now + duration, or next midnight.
  Changing the setting does not alter a token that's already running.

### Timer display

- Menu header while a timed token is active:
  `Active: deploy-bot — 23 min left (until 14:32)`; for Until midnight,
  `Active: deploy-bot — until midnight`; for the default,
  `Active: read-only (default)`.
- Menu bar: while a timed token with a finite duration is active, show the
  remaining minutes next to the icon (`23m`). Nothing extra for Until
  midnight or the default. *(Builder's call: refresh every ~30 s; switch to
  showing `<1m` in the last minute.)*

### Extend

- While a timed token is active, the menu shows `Add 30 min` (using the
  current Duration value). Clicking it pushes clearAt forward by that amount
  from the current clearAt. No Touch ID — the token is already live.
- When Duration is Until midnight, the item reads `Keep Until Midnight` and
  sets clearAt to the next midnight.
- *(Builder's call: hidden when the active token is the default or when
  the timed token is already set to midnight and Duration is Until midnight.)*

### When the timer runs out

Same triggers as today's clear: the timer, wake from sleep, app launch.

1. Default set, its plaintext in memory (for that same id), and the default
   not expired (`TokenEntry.isExpired()` on the vault's `expiresAt`; a
   revoked default surfaces as a failed `gh auth login`, see 3) → `gh auth login` with the default; state becomes default-active
   with no timer; drop the in-memory copy; notify
   `Back to “read-only” (default).`
2. Otherwise (no default, not in memory because the app was relaunched, or
   default expired) → log out as today; notify, e.g.
   `“deploy-bot” cleared. Pick the default in the menu to restore it.`
   or, for an expired default, say so.
3. If the `gh auth login` for the default fails → fall back to logout, keep
   today's retry-every-60s behaviour for an overdue clear.

### Other menu actions

- Activating another token while a timed one runs: switch to it, new timer
  from the current Duration.
- Activating the default while a timed token runs: switch to the default,
  no timer, drop the in-memory copy.
- `Deactivate Now`: logs `gh` out entirely, as today, and drops the
  in-memory copy. *(Builder's call: while a timed token is active and the
  default is in memory, also show `Switch to Default Now`.)*
- The currently active token's row stays disabled, as today (Extend covers
  "more time").

## Data model changes

- `TokenEntry.tag: TokenTag?` — new `enum TokenTag: String, Codable { green, orange, red }`.
- `VaultFile.defaultTokenId: UUID?`.
- Both optional so existing vault files decode unchanged (synthesized
  Codable uses `decodeIfPresent` for optionals).
- `ActivationState`: `clearAt == nil` with an active id means "no timer"
  (the default). Add one optional persisted field, `untilMidnight: Bool`, so
  the header, countdown and Extend item know whether a finite timer or
  Until midnight is running. *(Claude's call: an explicit flag rather than
  inferring it from whether clearAt falls on a midnight.)*
- Duration in UserDefaults (`activationDuration`), e.g. as minutes with a
  sentinel for midnight, or a small Codable enum in Core.

## Where the logic goes

- Core (unit-tested, no UI): `TokenTag`, the duration enum and its
  `clearAt(from:)` computation (reusing `nextMidnight`), and a pure decision
  function for "deadline reached" — given state, default id, whether the
  default is in memory, and whether it is expired → `.switchToDefault` or
  `.logout(reason)`. Tests cover every branch above.
- App: AppState holds the in-memory default secret, performs the switch,
  publishes a ticking `now` for the countdown; MenuContentView gains the
  Duration submenu, Extend, dots, header text; ManageView gains tag picker
  and default toggle; MenuBarIcon gains tint + countdown text.

## Implementation notes

- **Coloured menu bar icon:** template images are always drawn monochrome,
  so the tinted state needs a non-template image — draw the template PNG
  into a new NSImage filled with the tag colour (`sourceAtop`), and keep the
  template path for untagged/inactive so it still adapts to light/dark menu
  bars.
- **Coloured dots in menu rows:** SwiftUI `.menu`-style MenuBarExtra may
  render symbol images as monochrome; if `Image(systemName: "circle.fill")
  .foregroundStyle(color)` comes out grey, use a non-template NSImage dot.
- `Notifier` only posts text; the relaunch-fallback notification tells
  David to use the menu rather than being clickable (simplest).

## Tests / manual checklist additions

- Core unit tests: tag and defaultTokenId round-trip and absence in old
  vault JSON; duration → clearAt (incl. midnight); deadline decision table.
- Manual: tag a token, activate, icon colour matches; set Duration 15 min,
  activate a red token (one touch), countdown appears, Add 15 min works,
  timer end switches to the default without a prompt and the icon turns
  green; quit + relaunch mid-timer → at deadline it logs out with the
  restore hint; no default set → behaves as before; debug "Clear in
  1 Minute" exercises the switch.
- README: update "How it works" and the manual checklist for the new
  behaviour, and soften the "until midnight" promise (the default stays
  live).
