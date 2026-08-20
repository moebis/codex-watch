---
status: superseded
contract_ids: [PRIVACY-BOUNDARY-003, USAGE-ANALYTICS-010]
supersedes: []
superseded_by: 008-api-dashboard-and-refresh
owner: project-maintainer
created_at: 2026-08-20
last_verified_commit: pending
---

# Read bounded aggregate usage from the Codex analytics endpoint

## Context

The quota response reports remaining rate-limit percentages but not recent absolute token totals. The official Codex analytics page obtains daily aggregate tokens, turns, and threads from a separate authenticated read-only path on the same ChatGPT host.

## Decision

- Request only the inclusive trailing 30 calendar days from `/backend-api/wham/analytics/daily-workspace-usage-counts` with `group_by=day` and `workspace_user=true`.
- Reuse the existing credentials and ephemeral session, and apply the same HTTPS, host, redirect, cache, cookie, timeout, and one-mebibyte response limits.
- Require `group_by=day`, valid unique row dates inside the requested interval, and complete nonnegative token, turn, and thread totals; reject malformed, duplicated, out-of-range, incomplete, negative, or overflowing aggregates.
- Fetch analytics at launch and on manual refresh, but no more than once every 15 minutes during automatic 60-second quota refreshes.
- Treat analytics as best-effort. Keep quota working and retain only the last successful summary in process memory when analytics fails.
- Provide an explicit action that opens the official full analytics page in the user's default browser.

## Rejected alternatives

- **Scan local rollout logs:** this would expose prompts and conversation metadata and violate the privacy boundary.
- **Scrape or embed the analytics page:** HTML and browser state are brittle and introduce cookies and a larger attack surface.
- **Show lifetime totals or streaks:** the verified aggregate route is period based and does not establish those values.
- **Refresh every minute:** the dashboard data does not need quota-level polling frequency.

## Consequences

Codex Watch makes one additional same-host request at most every 15 minutes while running, plus explicit manual refreshes. The route is not a documented public API, so the menu must continue to fail closed and preserve quota behavior if it changes.

This decision was superseded by [008-api-dashboard-and-refresh](008-api-dashboard-and-refresh.md), which expands the bounded request to 365 days and defines the native projections, activity-only state, CSV export, and coordinated refresh behavior.
