---
status: active
owner: project-maintainer
last_verified_commit: a3db739
---

# Codex Watch architecture

This is the current structural authority for Codex Watch. Behavioral details belong in the active contracts and architecture decisions; release history remains in Git.

## Runtime snapshot

| Concern | Current choice |
|---|---|
| Product | Native macOS menu bar app, `LSUIElement` |
| Toolchain | Swift Package Manager, Swift tools 5.9, Swift 5 mode |
| Platform | macOS 14 or newer |
| UI | AppKit lifecycle, status item, menu, and window; SwiftUI plus Charts dashboard |
| Dependencies | Apple frameworks only; no third-party packages |
| Persistence | UserDefaults for preferences and window frame; explicit user-selected CSV only |
| Distribution | Ad-hoc hardened-runtime local build; tag-driven universal GitHub release |

## Data flow

```text
Codex executable -> experimental app-server JSONL over stdio
    -> managed ChatGPT authentication, quota, account usage, reset credits
    -> one-mebibyte line framing and fail-closed DTO validation

Optional CODEX_HOME/auth.json or ~/.codex/auth.json
    -> bounded off-main credential read
    -> ephemeral same-host HTTPS compatibility client
    -> richer analytics and profile DTO validation

Both paths
    -> immutable in-memory domain state
    -> native menu and reusable analytics window
    -> optional user-selected atomic CSV export
```

No response, token, account identifier, or analytics dataset is logged or cached. Missing, malformed, negative, non-finite, duplicate, out-of-range, or overflowing fields fail closed instead of being estimated.

## Component ownership

| Layer | Primary types | Responsibility |
|---|---|---|
| Lifecycle | `CodexWatchApp`, `AppDelegate` | Accessory-app startup, wake observation, shutdown |
| Menu orchestration | `MenuBarController`, `MenuBarPresentation` | Status item, native menu, refresh publication, truthful stale state |
| Refresh | `RefreshCoordinator`, `RefreshPolicy` | Trigger coalescing, generation ownership, cadence, cancellation |
| App-server transport | `CodexAppServerClient`, `ProcessAppServerLineTransport` | Managed-auth JSONL RPC over a local Codex child process with bounded line framing |
| Compatibility transport | `CodexAuthReader`, `CodexUsageClient` | Optional bounded local credential read and bounded authenticated GET requests |
| Source strategy | `CodexAccountService`, `CodexDataSourceStrategy` | Prefer official quota, retain narrow compatibility fallback, and merge independent capability results |
| Decoding | Usage, analytics, and profile DTOs | Untrusted payload validation and fail-closed conversion |
| Domain | `UsageSnapshot`, analytics/profile models | Immutable sendable state and pure calculations |
| Dashboard | Dashboard models/views, `AnalyticsWindowController` | Range projection, Lifetime presentation, reusable native window |
| Export | `UsageAnalyticsCSVExporter` | Formula-safe RFC 4180 CSV for the selected validated projection |
| User controls | Notification, launch-at-login, diagnostics, and reset-credit services | Explicit opt-in or confirmed actions with privacy-safe presentation |

## Trust and privacy boundaries

- `CodexAppServerClient` launches a locally installed Codex executable with the `app-server` command, completes the required initialize handshake, and permits only the account methods Codex Watch uses. Stdio messages have a one-mebibyte ceiling and each request has a 20-second timeout. Child stderr is discarded so private server diagnostics cannot enter app output.
- The app-server command is currently documented as experimental. Codex Watch therefore preserves its bounded same-host HTTPS path as a compatibility fallback and as the richer Usage analytics source.
- Managed ChatGPT authentication is owned by Codex and may use its configured file, keyring, or automatic credential store. Codex Watch does not read or copy keyring credentials.
- When available, `CodexAuthReader` reads only `auth.json`, requires a regular file, and enforces the one-mebibyte ceiling while reading from the opened handle. The read runs at utility priority outside the main actor.
- `SecureUsageSession` is ephemeral, uncached, and cookieless. Authenticated requests require HTTPS and the original ChatGPT host and effective port; cross-host redirects are rejected.
- `CodexUsageClient` consumes response bytes incrementally and stops after one mebibyte. The reset-credit detail request is optional and has a shorter timeout.
- The only authenticated destinations are the quota, reset-credit, bounded daily analytics, and profile paths on the original ChatGPT origin.
- Profile identity and editing fields are ignored. Lifetime values come only from validated server profile statistics, never from local sessions or partial analytics history.
- CSV is written atomically only after `NSSavePanel` returns a user-selected destination. Lifetime data is not exported.
- Quota notifications are off by default and contain no quota percentage or account value. macOS owns notification authorization and delivery persistence. Launch at Login is changed only through the user-selected menu toggle.
- Reset-credit consumption requires a confirmation, uses the documented idempotency key, retains an uncertain request only in memory for safe retry, and always refetches after an exact server outcome.
- Copy Diagnostics writes only version, selected source, capability freshness, and settings state to the pasteboard. It excludes credentials, account identifiers, paths, usage values, and error details.
- The app does not inspect rollout logs, prompts, browser cookies, Keychain browser material, process lists, or the Codex task database. It has no updater, telemetry, WebView, executable plugin system, or third-party network destination.

## Concurrency and lifecycle

- AppKit owners and UI mutations are main-actor isolated.
- Credential readers, transport state, refresh requests, results, and concurrent refresh closures are sendable.
- Quota, analytics, and profile attempts start together only when analytics cadence is eligible and fail independently.
- Repeated automatic triggers share active work. Manual refresh creates a new generation, cancels older work, and prevents stale publication.
- Menu opening is quota-only and refreshes only when the last successful quota snapshot is older than 60 seconds.
- App-server rate-limit update notifications trigger a coalesced quota-only refresh. They never bypass generation ownership or the analytics cadence.
- Scheduled delays begin after fetch completion. `stop()` cancels scheduled and active tasks, invalidates the session, removes the status item, and prevents later publication.
- Authentication failure may preserve prior in-memory analytics and profile values, but both surfaces must be marked stale.

## Presentation semantics

- The menu-bar number is always the rounded remaining base-weekly percentage. It never switches to a rolling, Spark, or model-specific limit.
- The status item uses the template `chart.pie.fill` SF Symbol and native foreground rendering so both icon and percentage adapt to light, dark, and selected materials.
- Spark capabilities remain decoded but any identifier equal to `codex-spark` or beginning with `codex-spark-` is omitted from the compact menu, including server-generated duplicate suffixes.
- Usage and Lifetime are distinct sources. The bounded 365-day dataset powers 7/30/90/365 projections; exact lifetime totals come from the profile route.
- Activity-only days, observed zero-token days, and missing days remain distinct. Model rows describe activity; client rows describe tokens.
- The heatmap uses seven weekday rows and as many week columns as the selected range needs. Model and client tables scroll horizontally instead of clipping narrow windows, and the dashboard refresh button invokes the same manual generation as the menu.

## Persistence

UserDefaults stores only:

- refresh frequency;
- compact-menu `30 Days` or `Lifetime` selection;
- dashboard range and section selection;
- quota-notification opt-in;
- the analytics window frame through AppKit autosave.

Quota, credentials, analytics, profile statistics, refresh timestamps, and errors remain process-local.

## Build and release

- `./scripts/check_contracts.sh` validates the active behavior-contract schema.
- `swift test` runs deterministic unit and integration tests.
- `./scripts/verify.sh /private/tmp/codex-watch-verify` validates contracts, tests, release compilation, Info.plist, ICNS representations, signature, and optional architectures outside synced storage.
- `./scripts/release.sh /private/tmp/codex-watch-release` creates the verified ZIP and SHA-256 file. `ARCHITECTURES="arm64 x86_64"` produces the universal artifact.
- CI verifies executable changes pushed to `main`; narrowly scoped non-executable authority changes are excluded. A `vMAJOR.MINOR.PATCH` tag must match `CFBundleShortVersionString` before the release workflow publishes assets.
- Local bundles are ad-hoc signed with hardened runtime. The repository has no Developer ID or notarization credentials.
- Build and sign outside File Provider or other synced repository paths. Auto-attached Finder metadata makes strict signature verification fail even when the compiled bundle is otherwise valid.

## Explicit constraints and deferred decisions

- The app is intentionally unsandboxed because it directly reads the existing Codex credential file. Enabling App Sandbox requires a separate authentication or security-scoped-access design; do not toggle it as a packaging-only change.
- ChatGPT endpoints are internal and may change. Preserve independent failures, stale labeling, bounded reads, and truthful unavailable states when adapting schemas.
- New hosts, private-data persistence, local-history indexing, multi-account support, providers, updater behavior, or additional state-changing API calls require explicit contracts and an architecture decision.
- Do not restore completed implementation plans. Distill durable behavior here, in `docs/PROJECT_MEMORY.md`, contracts, or active decisions; use Git history for release archaeology.
