# Codex Watch Lifetime and Icon Design

## Goal

Ship Codex Watch 1.2 with a reliably visible menu-bar mark, a shorter Codex-focused quota menu, verified macOS app-icon representations, and an exact server-reported Lifetime dashboard.

## Observable changes

- The status item uses a compact colored monitoring mark that remains legible against light, dark, and selected menu-bar backgrounds.
- The expanded quota menu no longer displays the `codex-spark` or `codex-spark-weekly` windows. Other base, additional, and code-review quota windows remain eligible for display.
- The analytics window has two top-level tabs: `Usage` and `Lifetime`.
- `Usage` preserves the existing 7-, 30-, 90-, and 365-day aggregate views and CSV export behavior.
- `Lifetime` displays the exact account summary returned by ChatGPT: lifetime tokens, peak daily tokens, longest chat, current streak, and longest streak. It also displays the server-provided daily token activity, activity insights, and top Codex plugin or skill invocations when present.
- Version becomes 1.2.0 with build number 17.

## Data source and semantics

Codex Watch performs a bounded read-only GET of `/backend-api/wham/profiles/me` on the same HTTPS origin as the existing quota endpoint. The request uses the existing ephemeral no-cookie session, bearer credential, optional `ChatGPT-Account-Id` header, same-host redirect policy, timeout, and one-mebibyte response ceiling.

Only the `stats` fields needed by the Lifetime view are decoded. Profile name, username, picture, and editable profile data are ignored. The response is kept only in process memory and is never logged, cached, automatically exported, or written to disk.

Lifetime totals are not derived from the bounded 365-day analytics dataset. Missing, malformed, negative, non-finite, or overflowing values are rejected or represented as unavailable; they are never replaced with estimates. A profile request failure does not block weekly quota or the existing Usage dashboard, and the last valid in-memory Lifetime result may remain visible with the existing stale-data treatment.

The daily profile buckets are server-reported account activity. They power the Lifetime activity heatmap but do not provide input/output/client/model breakdowns. Those breakdowns remain exclusive to the bounded Usage views.

## Lifetime model

Add a focused `CodexProfileStats` model containing:

- `lifetimeTokens: Int64?`
- `peakDailyTokens: Int64?`
- `longestRunningTurnSeconds: Int64?`
- `currentStreakDays: Int?`
- `longestStreakDays: Int?`
- validated unique daily buckets with start date and token count
- optional activity insight values for fast-mode percentage, reasoning effort, reasoning percentage, unique skills, total skill invocations, and total chats
- validated top invocations with a stable identity, display name, kind, and run count
- `fetchedAt`

The decoder accepts optional fields independently so a partial server response can still present truthful values. Daily bucket dates must be valid ISO calendar dates, token counts and run counts must be nonnegative, duplicate dates are rejected, and all accepted integer values must fit the destination type.

## Refresh behavior

The profile request joins the analytics branch of the existing refresh coordinator. It is attempted at launch, manual refresh, and eligible automatic analytics refreshes, never more frequently than the current 15-minute analytics cadence. Quota-only menu-open refreshes do not fetch profile data.

Quota, bounded analytics, and profile results fail independently. A successful profile result replaces the previous in-memory profile. A failed profile request preserves a previous valid profile and marks the analytics surfaces stale; without a previous profile, the Lifetime tab shows an unavailable state.

## Dashboard design

The analytics window adds a top-level segmented picker for `Usage` and `Lifetime`.

The Usage tab retains its current range picker, metric cards, heatmap, tables, export button, copy, sizing, and behavior.

The Lifetime tab contains:

1. Five headline cards matching the official concepts: Lifetime tokens, Peak tokens, Longest chat, Current streak, and Longest streak.
2. A calendar-style activity heatmap built only from validated server buckets. Cells expose an accessibility label with the date and token count. The section states the first and last observed dates rather than implying complete lifetime coverage.
3. Activity insights rows for the optional first-party values.
4. A top-invocations list for Codex plugins and skills, ordered by server count and rendered without loading remote icons.
5. Data-through, fetched, and stale indicators consistent with the Usage tab.

CSV export remains scoped to Usage. The Lifetime tab does not expose an export button in this release because the current export contract describes validated bounded projections only.

## Menu-bar icon

Replace the filled black pie symbol with a small deterministic AppKit-rendered monitoring mark: a cyan circular progress arc with a contrasting white terminal chevron and dark keyline. It is a non-template image so AppKit does not recolor it black while the status menu is selected. The high-contrast keyline and white center keep it distinguishable in light and dark appearances, while cyan connects it to the existing Codex Watch app icon.

The full app icon remains the approved `Resources/AppIcon.png` artwork. The icon builder continues producing the complete macOS ICNS set at 16, 32, 64, 128, 256, 512, and 1024 physical pixels. Bundle verification expands from checking only the 1024-pixel representation to checking every required iconset filename and its exact dimensions.

## Preserved contracts

- The menu-bar percentage remains rounded remaining base-weekly quota.
- The app stays a native `LSUIElement` with one status item and one reusable analytics window.
- Existing quota classification, reset credits, refresh-frequency choices, and 7/30/90/365 analytics calculations remain unchanged.
- Authenticated requests remain HTTPS, same-host, ephemeral, bounded, and in-memory.
- No updater, telemetry, WebView, cookies, session-log scanning, prompt reading, local history index, or third-party destination is added.
- No multi-provider support is introduced.

## Risk and verification

This is an L3 change because it adds an authenticated internal route, plus L2 visible UI and packaging changes.

Verification requires:

- DTO and model tests for complete, partial, malformed, duplicate, negative, and overflow profile fields.
- client tests for exact request path, headers, response ceiling, same-host enforcement, and independent failure behavior.
- refresh tests proving the profile request shares the analytics cadence and stale preservation rules.
- menu-presentation tests proving Spark windows are hidden while unrelated additional windows remain.
- dashboard-model tests for top-level tab state, Lifetime formatting, unavailable state, and server bucket projection.
- icon tests or executable verification covering menu-image properties and every ICNS representation.
- `swift test`, `./scripts/verify.sh`, and a local release build.
- manual validation of the installed status icon and Lifetime tab in macOS light and dark appearances, followed by app replacement and relaunch.
