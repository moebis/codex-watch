---
status: current
owner: project-maintainer
last_verified_commit: 5ab8abf
current_release: 1.2.2
current_build: 19
---

# Codex Watch project memory

This file is the compact handoff for future work. Read `ARCHITECTURE.md`, the active contracts, and the active decisions for normative detail.

## Current state

- Repository: `https://github.com/moebis/codex-watch`
- Upstream attribution: `https://github.com/smallyunet/codex-notch`
- Local checkout: `/Users/moebis/Documents/Codex/Codex Watch`
- Integration policy: work directly on `main`; do not create branches unless the user explicitly reverses that policy.
- Release 1.2.2 build 19 is commit `5ab8abf`. It was verified as a universal `arm64` and `x86_64` bundle, pushed to `origin/main`, installed, and relaunched on 2026-08-23. Recheck live machine state before relying on installation details.
- No `v1.2.2` tag or GitHub Release was created because only `main` publication was authorized.
- The working tree now targets 1.3.0 build 20 with app-server account transport, bounded compatibility fallback, user controls, dashboard layout fixes, and release-script hardening. On 2026-08-30 it passed contracts, 182 tests, complete strict-concurrency diagnostics, AddressSanitizer, ThreadSanitizer, signed local bundle verification, and an extracted universal archive round trip. It is not committed, pushed, installed, tagged, or released; real-menu notification, Launch at Login, reset confirmation, and dashboard visual acceptance remain owner-operated before publication.

## Durable product decisions

1. **Codex-only native scope.** Keep the focused AppKit and SwiftUI architecture. Do not import CodexBar's multi-provider, browser-cookie, updater, or dependency surface.
2. **Stable quota meaning.** The menu-bar percentage is the remaining base-weekly quota. Other windows may appear in the menu, but they never replace that number.
3. **Separate truthful sources.** Current quota comes from `/usage`; bounded range analytics comes from one trailing-365-day request; exact lifetime metrics come from `/profiles/me`. Never reconstruct lifetime totals from incomplete daily history or a manual baseline.
4. **Narrow privacy boundary.** Read only the existing bounded Codex auth file, contact only the original ChatGPT HTTPS host, retain authenticated data in memory, and export only a user-selected validated Usage projection.
5. **Independent capability failures.** Quota, Usage, Lifetime, and reset-credit detail may fail independently. Preserve last-good in-memory capability data only with explicit stale presentation.
6. **Native adaptive status presentation.** Use a template SF Symbol and native text color. Custom colored menu-bar artwork and forced foreground colors failed across macOS appearances.
7. **Spark is presentation-only filtering.** Decode Spark windows, but hide `codex-spark` and all `codex-spark-*` identifiers from the compact menu so duplicate suffixes do not leak back into the UI.
8. **No automatic updater.** Local builds and tag-driven GitHub releases are deliberate. Do not reintroduce update checks, downloads, or installs without an explicit security and product decision.
9. **Official account source with compatibility fallback.** Prefer the local Codex app-server for managed-auth quota, account usage, update notifications, and confirmed reset credits. Retain bounded same-host HTTPS only as the experimental-command fallback and richer aggregate analytics source.
10. **Explicit user controls only.** Notifications default off and contain no private values. Reset credits require confirmation and idempotent retry. Launch at Login and Copy Diagnostics are direct user actions; diagnostics contain operational state only.

## Lessons from the 1.2.2 engineering audit

- A metadata size check followed by `Data(contentsOf:)` is not a durable bound. Enforce limits while reading the opened file or response stream.
- Local file I/O must not run on the main actor. The credential read now uses a sendable abstraction and a utility-priority detached task with a hard one-mebibyte ceiling.
- Retained values after authentication failure are stale even when the last successful network request did not fail directly. Staleness describes current trust, not only the last capability call.
- Server-generated duplicate identifiers can gain numeric suffixes. Presentation filters must model the identifier family, not a short exact-value list.
- Actor and sendability annotations should describe actual ownership before adopting Swift 6 language mode. The source passes complete strict-concurrency diagnostics with warnings treated as errors while remaining in Swift 5 mode.
- The refresh coordinator's generation model is simpler and safer than independent repeating timers: automatic work coalesces, manual work replaces, and stale generations cannot publish.
- Leak-tool output from Apple frameworks is not evidence of a project leak. Prefer project-owned stack evidence, AddressSanitizer, ThreadSanitizer, stable runtime sampling, and bounded lifecycle review; never claim absolute leak freedom.

## 1.3.0 working-tree direction

- The Codex app-server uses JSONL over stdio and the required initialize handshake. Bound each line while reading, discard child stderr, validate request IDs and documented response variants, and ignore private thread-level account usage.
- The app-server command is currently experimental. Keep quota fallback independent from compatibility-only Usage analytics so keyring-authenticated users retain official account surfaces and file-authenticated users retain richer views.
- A rate-limit update is a quota-only refresh trigger. It coalesces with active work and never forces the bounded analytics request.
- Release verification must inspect the executable metadata before the one real build, extract the archive into a unique temporary directory, and verify the exact extracted app rather than a sibling or stale bundle.

## Security posture recorded on 2026-08-23

- A complete repository security review and a separate final working-tree diff review found no reportable vulnerabilities.
- Verified controls include one-mebibyte local and remote read limits, same-host and effective-port HTTPS enforcement, redirect rejection, ephemeral no-cookie networking, response validation, formula-safe CSV, hardened runtime signing, no dependencies, no updater, and no sensitive logging.
- The reviews used the documented parent fallback because delegated security workers were unavailable. TAC advisory enrichment was also unavailable. Future high-assurance reviews may repeat with independent workers and TAC access.
- Remaining hardening decision: App Sandbox. The current app has no entitlements and must read `~/.codex/auth.json`; sandboxing requires a deliberate credential-access design.
- Distribution remains ad-hoc signed and unnotarized until Developer ID credentials and a release policy are supplied.

## Verification and release routine

1. Read `AGENTS.md`, `ARCHITECTURE.md`, this file, active contracts, and relevant active decisions.
2. State the observable change, preserved behavior, exclusions, risk, and verification plan.
3. Add an outcome-oriented regression test for behavior changes.
4. Run `./scripts/check_contracts.sh`, `swift test`, and `./scripts/verify.sh /private/tmp/codex-watch-verify`.
5. For concurrency, authentication, parsing, or lifecycle changes, also run complete strict-concurrency compilation and the relevant sanitizer suites.
6. For distributable builds, run a universal `./scripts/release.sh`, preserve the previous installed bundle recoverably, verify the installed bundle, then relaunch and confirm the process remains alive.
7. Commit and push directly to `main` only when explicitly authorized. Create tags or GitHub Releases only when separately requested.

Build and sign outside File Provider or other synced repository paths. Those services can reattach Finder metadata to a bundle and invalidate strict signature verification; this is an output-location issue, not a reason to weaken verification.

## Documentation hygiene

- Current authority is limited to `README.md`, `AGENTS.md`, `ARCHITECTURE.md`, this file, active behavior contracts, active decisions, source, tests, and scripts.
- Completed release plans, superseded design specifications, and superseded decision files were removed after their durable constraints were consolidated. Git history remains the historical record.
- Do not store tokens, credentials, raw responses, member data, temporary paths, process IDs, or local rollback locations in repository memory.
