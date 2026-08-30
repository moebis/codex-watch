---
status: active
contract_ids: [PRIVACY-BOUNDARY-003, RESET-CREDITS-006, REFRESH-COORDINATION-013, DATA-SOURCE-015, USER-CONTROLS-016]
supersedes: []
superseded_by: null
owner: project-maintainer
created_at: 2026-08-30
last_verified_commit: a3db739
---

# Prefer managed Codex account APIs and keep user controls explicit

## Context

Codex Watch previously depended on direct access to `auth.json`. Current Codex documentation exposes managed account, rate-limit, account-usage, reset-credit, and update-notification methods through the local app-server. That supports Codex credential stores without copying secrets into this app. The app-server command is currently experimental, and the existing same-host HTTPS routes still provide richer bounded analytics. The product also needs useful alerts and system controls without expanding private-data retention.

## Decision

- Launch only a known installed Codex executable directly, without a shell, using `app-server` and the documented initialize handshake over JSONL stdio. Bound each input and output line to one mebibyte, time out unanswered requests after 20 seconds, discard child stderr, validate documented response shapes, and ignore account email and thread-level usage.
- Require a ChatGPT account. Prefer app-server quota and use bounded same-host HTTPS quota only when the official source is unavailable. Prefer the richer compatibility profile when available, then fall back to the reduced official account-usage summary. Keep the trailing 365-day Usage dataset compatibility-only.
- Treat app-server rate-limit updates as coalesced quota-only refresh triggers under the existing generation coordinator.
- Permit reset-credit consumption only through the documented app-server method after an explicit confirmation. Generate one UUID idempotency key, preserve an uncertain request only in memory for retry, clear it only after an exact outcome, and refetch after exact outcomes.
- Keep quota notifications off by default. Require macOS authorization, suppress stale data and repeat alerts, and use generic copy without percentages or account values.
- Expose Launch at Login through `SMAppService.mainApp`. Copy Diagnostics may include only version, quota-source name, capability freshness, and settings state.
- Preserve the same-host HTTPS path while app-server remains experimental. Do not add WebSocket transport, another host, telemetry, an updater, or private-data persistence.

## Rejected alternatives

- **Remove compatibility HTTPS immediately:** this would discard richer bounded Usage analytics and make an experimental command a single point of failure.
- **Continue file-only authentication:** users configured for keyring or automatic credential storage would be excluded and Codex Watch would keep duplicating credential handling.
- **Include quota percentages in notifications:** lock-screen content can expose private account state outside the app.
- **Automatically spend reset credits:** a state-changing account action requires explicit intent and a visible result.
- **Copy raw errors or paths for diagnostics:** operational support does not require credentials, account identifiers, filesystem layout, or usage values.

## Consequences

The app now owns a local child-process lifecycle and an experimental protocol dependency, so malformed input, termination, and missing executables must degrade to compatibility or unavailable state without leaking diagnostics. Keyring-authenticated users can receive official quota and reduced lifetime summaries without direct credential access. File-authenticated users retain richer bounded analytics. Notification authorization and launch registration are macOS-managed state, while all authenticated values and uncertain reset requests remain process-local.
