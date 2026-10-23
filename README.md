# GitHub Touch

A menu bar app that keeps GitHub tokens in a Touch ID vault and never
leaves one lying around: pick a token from the menu, touch the sensor,
and it's live in `gh`'s keychain — for 15 minutes, half an hour, an hour
or until midnight. Then `gh` falls back to your default token (say, a
read-only one) or, if you have none, is logged out.

## Why

`gh auth login` parks a broad, non-expiring token in the keychain
forever. GitHub Touch replaces that with a set of purpose-scoped tokens
(fine-grained or classic PATs) stored encrypted under a Secure Enclave
key. Only the one you activate exists outside the vault, and only for
as long as you chose.

## How it works

- Tokens are AES-GCM-encrypted, each under its own ephemeral ECDH
  against a P-256 key that lives in this Mac's Secure Enclave with a
  `userPresence` access control (Touch ID, password fallback). Only
  ciphertext and metadata hit disk:
  `~/Library/Application Support/github-touch/vault.json` (mode 600).
- Activating runs `gh auth login --with-token` with the token piped via
  stdin — it never appears on a command line or in a file.
- **Duration.** The menu's Duration submenu (15 min / 30 min / 1 hour /
  Until midnight) sets how long every activation lasts. While a timed
  token runs, the menu shows the time left and an "Add 30 min" (or
  "Keep Until Midnight") item; the menu bar shows the minutes left.
- **Default token.** Mark one token as Default in Manage Tokens. It runs
  without a timer, and when any other token's time runs out `gh`
  switches back to it. The touch that activates a timed token also
  unseals the default, which the app then holds **in memory only** so
  the switch back needs no prompt. If the app was quit or relaunched
  while a timed token ran, that copy is gone: at the deadline it logs
  out instead and tells you to pick the default from the menu.
- **Colour tags.** Tag tokens green, orange or red in Manage Tokens
  (meaning is up to you — e.g. read-only / mixed / dangerous). The menu
  bar icon takes the active token's colour.
- Clearing runs `gh auth logout` (or switches to the default). It fires
  when the timer runs out if the app is running, on wake if the Mac
  slept through it, and at launch if the app wasn't running. "Deactivate
  Now" logs out on demand; "Switch to Default Now" goes back early.
- Metadata (label, permissions, expiry, notes, tag, default) is deliberately stored
  in plaintext so the menu can show what each token can do without
  prompting.

## Honest caveat

While a token is active it sits in the keychain exactly as exposed as
a normal `gh auth login`. The win is least-privilege scoping plus a
guaranteed expiry — not runtime protection of the active token. A
default token is the exception to the expiry: it stays in `gh`'s
keychain until something replaces it, so make it one you're happy to
leave lying around (read-only).

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
6. Touch ID cancel: start an activation, cancel the Touch ID prompt —
   the app must stay silent (no error notification).
7. First notification: on the very first activation, the notification
   permission prompt must not freeze the menu bar UI.
8. Tags: tag a token in Manage Tokens, activate it — the icon takes its
   colour and its menu row has a dot; an untagged token gives the plain
   icon.
9. One touch: set a default (green), Duration 15 min, activate a red
   token — exactly **one** Touch ID prompt; icon red with `15m` beside it.
10. Add 15 min → the header shows about 30 min left.
11. Switch back: let the timer run out (or use the debug build's
    "Clear in 1 Minute") — `gh auth status` shows the default, icon
    green, no prompt, notification "Back to …". Repeat with the Mac
    asleep over the deadline.
12. Relaunch mid-timer: activate a timed token, quit and relaunch, let
    it run out — logs out with "Pick the default in the menu".
13. Changed default: while a timed token runs, make another token the
    default — at the deadline it logs out rather than restoring either.
14. No default set → the deadline logs out as before.
15. Delete the active token (e.g. the default) in Manage → `gh` is
    logged out, not left live.
16. Duration submenu shows the four choices with one checkmark, and the
    choice survives a relaunch.

## License

Copyright © 2026 David Vrensk.
Released under the GNU General Public License v3.0 — see [LICENSE](LICENSE).
