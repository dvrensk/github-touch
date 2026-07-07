# GitHub Touch — Auto-generated Token Descriptions

Date: 2026-07-07
Status: approved pending user review
Extends: 2026-07-07-github-touch-design.md (v1 app, built on branch feature/github-touch)

## Goal

When a token is added or imported, the app writes its description itself: a
compact one-line `summary` for the menu row plus a fuller capability list in
the permissions field. The user never has to type a description, but can
edit the generated text before saving (and later in Manage).

Decisions from brainstorming:

- **No LLM.** The input vocabulary (classic scopes) is finite, and probing
  gives ground truth for fine-grained tokens; an LLM could only rephrase and
  would require storing another API key in a security-focused app. The
  DescriptionBuilder boundary is where an LLM could later plug in if ever
  wanted.
- **Fine-grained tokens are probed** with read-only API calls at add-time
  (user-approved; ~2s once per add).

## Components

### ScopeCatalog (GitHubTouchCore, pure)

Static table mapping classic/OAuth scope names to a plain-English phrase
and a `dangerous` flag:

| scope | phrase | dangerous |
|---|---|---|
| repo | read/write ALL repos | yes |
| public_repo | read/write public repos | no |
| delete_repo | delete repos | yes |
| admin:org | manage org | yes |
| write:org | write org data | yes |
| read:org | read org membership | no |
| gist | gists | no |
| workflow | edit Actions workflows | yes |
| notifications | notifications | no |
| user / read:user | read profile | no |
| user:email | read email | no |

Unknown scopes pass through verbatim (not dangerous). Lookup is by exact
scope string as returned in `X-OAuth-Scopes`.

### CapabilityProber (GitHubTouchCore)

For fine-grained tokens only. Given a validated token, runs a fixed battery
of read-only GETs against api.github.com, each with the token in the
Authorization header, a 5-second per-request timeout, injectable URLSession:

| endpoint | capability probed |
|---|---|
| `/user/repos?per_page=100` | repo access; on 200, the returned repo `name`s are exactly the repos the token can see |
| `/user/orgs` | org read |
| `/gists` | gist read |
| `/notifications` | notifications read |
| `/user/emails` | email read |

Result per probe: `.granted(detail)` on 200 (detail = repo names for the
repos probe, nil otherwise), `.denied` on 403 (additionally recording the
`X-Accepted-GitHub-Permissions` header value when present), `.unknown` on
network error/timeout. A 401 anywhere aborts: the token is invalid (should
not happen post-validation). Probes run concurrently; total wall time is
bounded by the slowest single probe.

Write access cannot be probed safely (probing would mutate); the summary
never asserts write capability for fine-grained tokens — it reports reads
as facts and appends "write: as configured" only if the user recorded write
permissions manually.

### DescriptionBuilder (GitHubTouchCore, pure)

`build(kind:scopes:probe:expiresAt:) -> (summary: String, details: [String])`

- Classic/OAuth: map scopes through ScopeCatalog. `summary` = phrases joined
  with ", ", dangerous ones prefixed "⚠", truncated with "…" at 60
  characters (never mid-word); `details` = one phrase per scope, dangerous
  ones prefixed "⚠", plus "expires <date>" when expiry is known.
- Fine-grained: `summary` built from granted probes, repos first with names
  ("repos: a, b (+3)" — first two names, "+N" for the rest), then other
  granted reads ("orgs, gists"); "no API read access found" if nothing
  granted. `details` = one line per probe: granted ("repo access: a, b, c"),
  denied ("no gist access"), unknown ("gist access: probe failed").
- Pure function; no I/O; fully unit-tested.

## Storage & UI

- `TokenEntry` gains `summary: String?` — optional and Codable-decoded with
  `decodeIfPresent`, so existing vault.json files load unchanged (no vault
  version bump).
- Menu row shows `summary` when present, else the existing permissions join.
- AddTokenView: after successful validation, generation runs automatically
  (classic: immediate; fine-grained: probe with a "Probing what this token
  can do…" progress line). Generated summary and details land in editable
  fields (`summaryText`, existing `permissionsText`) before Save.
- Import flow: generates the same way from the captured token's scopes
  (classic path — the legacy token is OAuth).
- ManageView: adds an editable Summary field per token row.

## Errors

- Probe failure/timeout is non-fatal: affected capabilities are reported as
  "probe failed" in details, summary falls back to whatever is known, and
  the user can edit before saving.
- Probes are read-only GETs, in-memory token handling identical to
  TokenValidator (never argv/file/pasteboard/log).

## Testing

- ScopeCatalog + DescriptionBuilder: pure unit tests (classic mapping,
  danger flags, truncation, fine-grained summary shapes, empty results).
- CapabilityProber: MockURLProtocol tests (same pattern as
  TokenValidatorTests): all-granted, mixed 200/403 with the
  X-Accepted-GitHub-Permissions header, network error → .unknown.
- Codable backward-compat test: vault JSON without `summary` decodes.
- One manual pass with a real fine-grained token (human).

## Out of scope

- LLM integration (explicitly rejected; DescriptionBuilder is the seam).
- Probing write permissions.
- Re-probing existing tokens on a schedule (regenerate only on add/import;
  Manage edits are manual).
