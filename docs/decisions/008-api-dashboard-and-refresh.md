---
status: active
contract_ids: [DASHBOARD-SURFACE-011, PRIVACY-BOUNDARY-003, USAGE-ANALYTICS-012, REFRESH-COORDINATION-013]
supersedes: [004-menu-bar-only, 007-usage-analytics]
superseded_by: null
owner: project-maintainer
created_at: 2026-08-20
last_verified_commit: pending
---

# Add a native Codex analytics dashboard and coordinated refresh

## Context

The compact 1.0 menu exposed a truthful 30-day usage summary but could not make daily trends, coverage gaps, model activity, client tokens, or multiple ranges easy to inspect. The official aggregate route can return a bounded year of daily rows, including older rows with valid activity but no token fields. Independent timers also made refresh ownership and stale publication harder to reason about.

## Decision

- Keep one persistent `NSStatusItem` whose title is the rounded remaining base-weekly percentage. Add one reusable, resizable native analytics window; keep the app an `LSUIElement` with no persistent Dock icon, notch overlay, or web view.
- Request the inclusive trailing 365 days once and derive 7-, 30-, 90-, and 365-day projections in memory. Missing dates, observed zero-token dates, and activity-only rows remain distinct.
- Report server model rows as turns, chats, credits, and turn share. Report client rows as server-provided tokens. Never infer per-model tokens or pricing.
- Require at least 90 percent token coverage in both periods before showing a 7-, 30-, or 90-day comparison. The 365-day comparison remains unavailable because the bounded request does not contain the preceding year.
- Export only the selected validated projection, and only after the user chooses a CSV destination. Do not cache analytics or export automatically.
- Route launch, automatic, manual, menu-open, and wake triggers through one refresh coordinator. Automatic triggers coalesce, a manual generation supersedes older work, delayed scheduling starts after completion, and stopped or stale generations cannot publish.
- Offer Manual, Adaptive, 1-, 2-, 5-, 15-, and 30-minute quota choices. Adaptive uses only recent menu interaction plus Low Power Mode and thermal pressure; it never scans processes, sessions, prompts, or browser state. Automatic analytics attempts remain at least 15 minutes apart.

## Rejected alternatives

- **Put every metric in the status menu:** charts, coverage, range selection, and long model/client tables are not legible in a native menu.
- **Import a multi-provider architecture:** Codex Watch does not need browser-cookie extraction, provider abstractions, an updater, or third-party network destinations.
- **Scan local sessions for richer metrics:** local history is a separate future decision because it changes the privacy boundary and retention model.
- **Embed the official analytics page:** a web view would add cookies, browser state, and a larger attack surface.
- **Treat absent historical token fields as zero:** those rows carry valid activity but do not establish token observation.

## Consequences

Codex Watch 1.1 provides a larger Codex-only metrics surface while preserving the authenticated same-host and in-memory privacy boundary. The internal ChatGPT routes may change, so optional fields fail closed, quota remains independently useful, and stale successful analytics stays visibly marked rather than being replaced with fabricated data.

Companion widgets, notifications, a local history index, WebView-only product metrics, and multi-account support require separate decisions and are not part of this release.
