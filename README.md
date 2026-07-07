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
6. Touch ID cancel: start an activation, cancel the Touch ID prompt —
   the app must stay silent (no error notification).
7. First notification: on the very first activation, the notification
   permission prompt must not freeze the menu bar UI.

## License

Copyright © 2026 David Vrensk.
Released under the GNU General Public License v3.0 — see [LICENSE](LICENSE).
