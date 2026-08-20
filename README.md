# Codex Watch

Codex Watch is a native macOS menu bar app for monitoring ChatGPT Codex quota, token usage, and activity. Version 1.2 adds exact first-party lifetime profile statistics, a more visible status mark, and a shorter Codex-focused menu while keeping the menu-bar percentage focused on the base weekly quota.

## What it shows

- The rounded percentage remaining in the base weekly Codex quota, always visible in the menu bar.
- Every valid base and code-review quota window returned by ChatGPT, including remaining percentage, reset countdown, and progress. Codex Spark limits remain decoded but are intentionally hidden from the compact menu.
- Deterministic quota pace (`On pace`, `in reserve`, or `in deficit`) once at least 3% of a server-provided window has elapsed. Pace is a linear snapshot, not a probability or entitlement estimate.
- The recognized ChatGPT plan, credits balance or `Unlimited`, available reset-credit count, and the earliest supported reset-credit expiry when present.
- A compact 30-day menu summary for total, uncached-input, cached-input, and output tokens plus turns, chats, token coverage, and server data-through date.
- A reusable native dashboard whose Usage tab provides 7-, 30-, 90-, and 365-day ranges, summary cards, an Apple Charts token chart, an accessible activity heatmap, model activity, and client token totals.
- A Lifetime tab with exact server-reported lifetime tokens, peak daily tokens, longest chat, current and longest streaks, daily token activity, activity insights, and most-used Codex plugins or skills.

Model rows report turns, chats, credits, and turn share because the endpoint does not provide per-model token counts. Client rows report server-provided token fields. Dates with activity but no historical token fields are labeled `Activity only`; they are not treated as zero-token or missing days. Period comparisons appear only when both periods have at least 90% token coverage, and the 365-day range does not claim a comparison.

## Controls and refresh behavior

The menu includes:

- `Refresh Now`
- `Refresh Frequency`: Adaptive, Manual, 1, 2, 5, 15, or 30 minutes
- `Open Analytics Dashboard…`
- `Open Usage Analytics…` for the official ChatGPT web page
- `Open ChatGPT`
- Quit

Adaptive refresh is the default for a fresh preference domain. It checks every 2 minutes after recent menu interaction, then backs off to 5, 15, or 30 minutes. Low Power Mode and serious or critical thermal pressure use 30 minutes. Opening the menu requests fresh quota only when the last successful snapshot is older than 60 seconds. Bounded Usage analytics and Lifetime profile statistics are fetched on manual refresh and no more than once every 15 minutes automatically.

Automatic triggers share active work. A manual refresh replaces older background work, and stale generations cannot publish. Quota errors preserve and dim the last successful percentage with an `Updated … ago` label. Usage and Lifetime failures are independent: each preserves its own last successful in-memory result and marks only that dashboard surface stale.

## CSV export

`Export CSV…` in the native dashboard exports only the currently selected projection after you choose a destination. The RFC 4180 CSV contains range metadata, coverage, every daily state, model activity, and client token totals. Server-supplied labels are protected against spreadsheet-formula injection. Codex Watch never chooses an export path or writes analytics automatically.

## Authentication and privacy

Codex Watch reads `tokens.access_token` and `tokens.account_id` from `CODEX_HOME/auth.json`; when `CODEX_HOME` is unset, it uses `~/.codex/auth.json`.

Credentials are used in memory only for read-only requests on the original ChatGPT HTTPS host:

```text
GET https://chatgpt.com/backend-api/wham/usage
GET https://chatgpt.com/backend-api/wham/rate-limit-reset-credits
GET https://chatgpt.com/backend-api/wham/analytics/daily-workspace-usage-counts
GET https://chatgpt.com/backend-api/wham/profiles/me
```

The Usage analytics request covers the inclusive trailing 365 calendar days. Smaller views are projected locally from that one bounded response. The profile request supplies exact Lifetime headline totals and its own daily activity buckets; those values are never reconstructed from incomplete historical rows. Each response is capped at one mebibyte. The production network session is ephemeral, uncached, cookieless, and rejects redirects to another host.

Authenticated responses remain in process memory. Codex Watch never logs credentials, headers, response bodies, account identifiers, analytics values, or export paths. It does not read rollout JSONL, the Codex task database, prompts, titles, project paths, browser cookies, Keychain browser material, or process lists. It adds no telemetry, updater, automatic download, hidden web view, or third-party network destination.

The ChatGPT routes are internal and may change without notice. Missing or changed optional fields are hidden or marked partial rather than guessed. Codex Watch does not infer absolute token allowances, missing lifetime totals, streaks, plugin use, skill use, reasoning modes, or pricing.

## Install

Requirements: macOS 14 or newer, Xcode 15 or newer, and Swift 5.9 or newer.

Build and verify a local app bundle, then copy it to Applications:

```sh
./scripts/verify.sh /private/tmp/codex-watch-build
ditto "/private/tmp/codex-watch-build/Codex Watch.app" "/Applications/Codex Watch.app"
```

The local release is ad-hoc signed because this repository does not contain an Apple Developer ID certificate. macOS may require Control-clicking the app and choosing **Open** on first launch.

## Build, test, and release

```sh
./scripts/check_contracts.sh
swift test
./scripts/verify.sh
```

Create a local universal release archive:

```sh
ARCHITECTURES="arm64 x86_64" ARCHIVE_ARCH=universal ./scripts/release.sh
```

A `vMAJOR.MINOR.PATCH` tag matching `CFBundleShortVersionString` triggers the GitHub release workflow. CI tests, builds, verifies, archives, checksums, and publishes the app; it rejects a mismatched tag.

## License and attribution

MIT License. See [LICENSE](LICENSE).

Codex Watch is derived from [CodexNotch by smallyunet](https://github.com/smallyunet/codex-notch). The original copyright and license notice are preserved. The Codex-only analytics architecture also drew practical inspiration from [CodexBar](https://github.com/steipete/CodexBar/) while intentionally excluding its multi-provider, browser-cookie, and updater surface.
