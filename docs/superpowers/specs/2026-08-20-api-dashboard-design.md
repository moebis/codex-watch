# Codex Watch 1.1 API Dashboard Design

## Status

- Proposed release: `1.1.0` (build `16`)
- Product: Codex Watch for macOS 14 and newer
- Repository branch: `main` only
- Design scope: authenticated Codex quota and server analytics
- Follow-on scopes: local history index; companion surfaces and optional web extras

## Goal

Turn Codex Watch from a compact quota reader into a Codex-focused usage dashboard while preserving the menu bar's stable weekly percentage and the existing same-host credential boundary.

Version 1.1 will expose all trustworthy data already present in the authenticated ChatGPT usage and workspace-analytics responses. It will add an on-demand native dashboard, richer quota detail, daily activity, model and client breakdowns, pace, freshness, coverage, and non-overlapping refresh behavior. It will not inspect Codex sessions or browser state.

## Scope decomposition

The broader Codex power-dashboard direction contains three independently testable subsystems:

1. **API dashboard and refresh reliability** — this design and release 1.1.
2. **Local Codex history index** — a later design covering bounded JSONL and thread-catalog indexing, model/project/session analytics, reasoning, cost estimates, streaks, and retained-history totals.
3. **Companion surfaces** — later designs covering widgets, CLI output, notifications, OpenAI service status, multi-account support, and optional WebView-only metrics.

This separation keeps release 1.1 useful on its own and avoids coupling a new dashboard to a 441 MB local-history migration or new macOS permissions.

## Considered approaches

### 1. Expand only the existing status menu

This is the smallest implementation and keeps the menu-bar-only contract intact. It becomes difficult to scan once daily charts, four selectable ranges, model rows, client rows, coverage, pace, and reset-credit inventory are present. Native menus are also a poor home for persistent selection and chart interaction.

### 2. Import CodexBar's provider architecture

This supplies mature fetch, history, widgets, and preferences infrastructure. It also brings abstractions for dozens of providers, third-party dependencies, browser-cookie handling, updater hooks, and a much larger state surface that Codex Watch does not need.

### 3. Add a Codex-only dashboard over focused data services

This is the selected approach. Codex Watch keeps its small Codex-specific domain model and adds an on-demand native dashboard backed by one validated usage snapshot and one validated analytics dataset. Refresh coordination and presentation remain independent, allowing the later local index to attach as another explicitly labeled source without redesigning the API dashboard.

## Product behavior

### Menu bar

The single `NSStatusItem` remains the app's persistent surface. Its title remains the rounded remaining percentage of the base weekly quota window. Extra windows never replace that number.

The status menu remains compact and contains:

- Plan and credit-balance rows when server-reported.
- The base weekly quota and reset progress.
- Every valid additional model-specific quota window, including its remaining percentage, duration label, reset countdown, and progress.
- Deterministic pace for windows with enough timing information.
- Available reset-credit count and the earliest expiry summary.
- Analytics freshness and coverage summary.
- `Open Analytics Dashboard…`, `Refresh Now`, `Open ChatGPT`, and quit actions.

The menu must not embed the full heatmap or long model/client lists.

### Analytics dashboard

`Open Analytics Dashboard…` opens one reusable native window. Codex Watch remains an `LSUIElement` app and does not gain a persistent Dock icon. Closing the window releases its presentation hierarchy; reopening uses the latest in-memory snapshot.

The dashboard contains:

1. A range selector for 7, 30, 90, and 365 calendar days.
2. Summary cards for total, uncached-input, cached-input, and output tokens, turns, and chats.
3. Previous-period deltas for 7, 30, and 90 days when both periods have complete enough coverage. A 365-day comparison is unavailable because it would require more than the bounded 365-day request.
4. A daily token chart and a 365-cell activity heatmap. Missing dates render as gaps, not zero-token days.
5. A model-activity table aggregated from the server's model rows: model name, turns, chats, credits, and share of turns. It must not label these rows as per-model token usage because that field is not supplied.
6. A client-token table aggregated from client rows: client name, total, uncached-input, cached-input, and output tokens, turns, and chats.
7. Data-source, fetch-time, server-data-through, observed-day, and missing-day labels.
8. A user-initiated CSV export of the currently selected projection.

The window uses native AppKit/SwiftUI and Apple Charts APIs only. No web content or third-party UI package is embedded.

## Remote data model

### Quota endpoint

`GET https://chatgpt.com/backend-api/wham/usage` remains authoritative for current quota and account summary.

The decoder adds these optional capabilities:

- `additional_rate_limits[]`, decoded per element so one malformed entry cannot discard valid siblings or the base quota.
- Each extra entry's `limit_name`, `metered_feature`, and nested primary/secondary windows.
- Plan-dependent `code_review_rate_limit` when it uses a recognized rate-window shape.
- Plan-dependent `spend_control.individual_limit` summary when complete and nonnegative.
- Full current reset-credit inventory from the existing reset-credit detail endpoint, not only the earliest expiry.

Dynamic identifiers derive from a bounded slug of `metered_feature` or `limit_name`. GPT-5.3-Codex-Spark receives stable identifiers for its five-hour and weekly windows. Unknown valid limits display their bounded server name without changing the menu-bar percentage.

### Analytics endpoint

Codex Watch makes one request for the inclusive trailing 365 calendar days:

`GET /backend-api/wham/analytics/daily-workspace-usage-counts?start_date=…&end_date=…&group_by=day&workspace_user=true`

Smaller dashboard ranges are derived in memory from that bounded response. Automatic analytics refresh remains no more frequent than every 15 minutes; manual refresh may request it immediately.

Each daily row is validated independently:

- The date must be a valid unique local calendar date inside the requested range.
- Daily total fields must be complete, nonnegative, finite where applicable, and non-overflowing.
- Model and client arrays are additive capabilities. Invalid nested entries are skipped individually and mark that breakdown partial; they do not discard valid daily totals or sibling entries.
- Model names and client identifiers are trimmed, bounded to 128 UTF-8 bytes, and grouped by their exact normalized value.
- Credits are decimal values and are never converted into token counts.

The resulting in-memory dataset records its request interval, observed dates, first and last observed date, missing-date set, fetch time, and per-breakdown completeness.

## Coverage and comparison semantics

The dashboard distinguishes four states:

- **Observed:** a valid server row exists for that date, including a valid zero.
- **Missing:** no row exists for a requested date.
- **Partial model/client detail:** daily totals are valid but one or more nested breakdown entries were unusable.
- **Unavailable:** no valid dataset has been fetched in this process.

Totals may be displayed for a selected range containing missing dates, but the range is labeled with observed-day coverage and `Data through <date>`. Period-over-period percentage deltas require both periods to meet a 90 percent observed-day threshold and to have valid nonzero comparison denominators. Otherwise the comparison displays `Unavailable` rather than a misleading change.

The heatmap reserves a distinct visual state for missing dates. Accessibility labels identify the date and whether it is observed, zero, or missing.

## Pace semantics

Pace compares actual used percentage with the elapsed percentage of the server-provided window:

- It requires a positive duration and a future reset inside that duration.
- It is hidden until at least 3 percent of the window has elapsed.
- `In deficit` means actual use is ahead of even consumption; `In reserve` means it is behind.
- A projected exhaustion time is shown only when current linear consumption would exhaust the remaining capacity before reset.
- No probability, workday calibration, or historical forecast is claimed in release 1.1.

Pace is presentation guidance, never an entitlement or allowance estimate.

## Refresh architecture

`MenuBarController` will stop owning request-generation details. A focused refresh coordinator will expose automatic, manual, and menu-open triggers.

- At most one quota/analytics refresh generation may publish at a time.
- Repeated automatic triggers coalesce into the active request.
- A manual refresh replaces older background work and its generation alone may publish.
- Scheduled delays begin after the prior refresh completes, preventing catch-up bursts and timer drift.
- Opening the menu refreshes immediately only when the quota snapshot is older than 60 seconds.
- Fixed choices are Manual, 1, 2, 5, 15, and 30 minutes.
- Adaptive is the default for a new preference domain: 2 minutes when the menu was opened within 5 minutes, 5 minutes within 1 hour, 15 minutes within 4 hours, and 30 minutes otherwise.
- Low Power Mode or serious/critical thermal pressure selects 30 minutes.
- Existing installations without a stored preference retain the current 1-minute cadence. No process list or session activity is inspected.

The coordinator is testable through injected time and fetch closures. Cancellation, stale generations, and controller shutdown must not publish or retain the controller.

## Error and stale-data behavior

Quota remains the primary health signal. Analytics, extra limits, reset-credit detail, code-review detail, and spend-control detail are best-effort additions.

- A quota failure preserves the last successful snapshot in memory, dims the status item, and displays the error plus `Updated <relative time>`.
- An analytics failure preserves the last successful analytics dataset and labels it stale.
- A malformed optional field cannot remove the valid base weekly window.
- Authentication errors display `Sign in to Codex again` and never trigger token refresh or mutate `auth.json`.
- Response bodies, headers, credentials, account identifiers, analytics values, model/client values, and export paths are never logged.
- CSV export failure is shown to the user and does not alter in-memory data.

## Persistence and privacy

Release 1.1 keeps authenticated response data in process memory only. The only persistence is:

- UserDefaults for refresh preference, selected dashboard range, and window placement.
- A CSV file written only after the user chooses a destination in `NSSavePanel`.

The production session remains ephemeral, uncached, cookieless, bounded to one mebibyte per response, and restricted to HTTPS on the original ChatGPT host and port. Redirects to another host remain rejected.

The app does not read rollout JSONL, the Codex thread database, prompts, titles, project paths, browser cookies, Keychain browser material, or process lists in this release. It adds no telemetry, updater, automatic download, or third-party network destination.

## Component boundaries

- `UsageResponseDTO` decodes base and optional quota capabilities without presentation decisions.
- `UsageSnapshot` owns base and named windows, reset credits, optional plan-dependent metrics, source time, and data confidence.
- `UsageAnalyticsResponseDTO` validates the 365-day response and produces an immutable `UsageAnalyticsDataset`.
- `UsageAnalyticsProjection` derives range totals, coverage, comparisons, daily cells, model activity, client tokens, and CSV rows.
- `UsagePace` is a pure calculation over one window and a supplied date.
- `RefreshCoordinator` owns trigger coalescing, generations, scheduling, and cancellation but no AppKit objects.
- `MenuBarController` binds the latest state to the status item and owns one reusable `AnalyticsWindowController`.
- `AnalyticsDashboardView` renders a projection and emits range/export actions without performing network requests.

Each boundary has deterministic unit tests. Network tests continue to use the existing custom URL protocol at the authenticated request boundary.

## Contract changes required during implementation

Implementation must update the active harness before shipping:

- Supersede `MENU-BAR-001` with a contract that keeps the menu bar as the persistent control surface while permitting one user-opened analytics window and no Dock icon.
- Preserve `QUOTA-SEMANTICS-002`; extra windows never replace the base weekly percentage.
- Amend `PRIVACY-BOUNDARY-003` only to describe the wider bounded same-host analytics payload and user-initiated CSV export. Session scanning remains excluded in release 1.1.
- Preserve `PACKAGE-RELEASE-004`, `MENU-PROGRESS-005`, `RESET-CREDITS-006`, `PLAN-DISPLAY-008`, and `CREDITS-BALANCE-009` while adding separate optional rows.
- Supersede `USAGE-ANALYTICS-010` with the 365-day dataset, nested model/client capabilities, coverage semantics, selected-range projections, and best-effort stale-data behavior.
- Add a refresh contract covering coalescing, generation ownership, adaptive/fixed cadence, and shutdown cancellation.

The corresponding architecture decisions must record why an on-demand dashboard and wider server aggregate are now accepted while local history remains a separate explicit decision.

## Verification

Implementation follows strict red-green-refactor cycles and adds outcome-based guards for:

- Lossy additional-limit decoding, stable IDs, duration classification, and base-window preservation.
- 365-day query construction, response-size and same-host enforcement.
- Valid, malformed, duplicate, out-of-range, negative, overflowing, and partial daily/model/client rows.
- Range projection, observed/missing coverage, data-through dates, 90 percent comparison threshold, and CSV serialization.
- Pace boundaries, insufficient elapsed time, projected exhaustion, and invalid resets.
- Automatic coalescing, manual replacement, stale-generation rejection, menu-open freshness, adaptive decisions, cancellation, and shutdown.
- Menu presentation, dashboard presentation models, accessibility labels, and stale/error copy.
- Version, bundle identity, release archive, and absence of updater/session-scanner dependencies.

Before release:

1. Run `./scripts/check_contracts.sh`.
2. Run `swift test`.
3. Run `./scripts/verify.sh`.
4. Run `./scripts/release.sh`.
5. Install the newly built app over `/Applications/Codex Watch.app` using a recoverable replacement.
6. Relaunch it and inspect menu spacing, every returned quota window, dashboard ranges/charts, missing-day treatment, stale state, CSV export, version, bundle identifier, signature, and running process on a real Mac.
7. Commit and push only the intended paths directly to `main`; do not create a branch or pull request.

## Explicitly out of scope

- Local session or thread-catalog scanning.
- Lifetime or longest-chat claims.
- Reasoning-effort, skill, plugin, project, or session analytics.
- Local cost estimates or model pricing.
- Browser cookies, hidden WebViews, HTML scraping, or cross-app OAuth sources.
- OpenAI status-page polling or any new host.
- Notifications, WidgetKit, CLI output, multi-account switching, or automatic updates.
- Reset-credit redemption or any other state-changing ChatGPT request.
- Multi-provider abstractions.

These are not rejected permanently; each requires its own bounded design, contracts, tests, and release after 1.1 establishes the dashboard boundary.
