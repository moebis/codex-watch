# Codex Watch 1.0 Design

> Historical release design. Codex Watch 1.1 supersedes the analytics and surface decisions here; see the [Codex Watch 1.1 API Dashboard Design](../superpowers/specs/2026-08-20-api-dashboard-design.md). The 1.0 record remains unchanged below as release history.

## Goal

Rename CodexNotch to Codex Watch, give it an original app icon, and add truthful 30-day token-usage details without expanding the app into a browser, telemetry collector, or conversation-log reader.

## Product identity

- User-facing name: `Codex Watch`
- Swift package, product, executable, and module: `CodexWatch`
- Bundle identifier: `com.moebis.codexwatch`
- App bundle and icon: `Codex Watch.app` and `CodexWatch.icns`
- Repository: `moebis/codex-watch`
- Local directory: `/Users/moebis/Documents/Codex/Codex Watch`
- Version: `1.0.0` (build `15`)
- Attribution: preserve the MIT license and credit the original `smallyunet/codex-notch` project in the README.

## Icon direction

Use the generated raster master as a centered macOS app icon: a circular quota/watch ring around a terminal prompt, with near-black, warm-white, and electric-cyan colors. It must contain no text or copied OpenAI mark, remain recognizable at 16–64 px, and work against both light and dark system appearances.

## Usage analytics

Use the authenticated, read-only same-host endpoint already used by the official Codex analytics page:

`GET https://chatgpt.com/backend-api/wham/analytics/daily-workspace-usage-counts`

Send `start_date`, `end_date`, `group_by=day`, and `workspace_user=true` for the inclusive trailing 30 calendar days. Decode only daily aggregate totals and sum the following nonnegative fields:

- total text tokens
- uncached input tokens
- cached input tokens
- output tokens
- turns
- threads, displayed as chats

Analytics accepts only day-grouped rows with valid unique dates inside that requested interval and complete nonnegative non-overflowing totals. It is best-effort, held only in memory, capped at one mebibyte, and refreshed at launch, on manual refresh, and no more often than every 15 minutes during automatic quota refreshes. If it fails or changes shape, the weekly quota remains available and prior successful analytics may remain visible for the current process.

## Menu design

Keep the existing quota card first. When analytics is available, add a compact `Last 30 days` card with six aligned rows. Add `Open Usage Analytics…` to open the official dashboard in the default browser. Continue showing `Open ChatGPT` for the installed Codex app.

## Privacy and failure behavior

- Keep the production `URLSession` ephemeral, uncached, cookieless, and restricted to HTTPS on `chatgpt.com`.
- Never log or persist credentials, headers, response bodies, prompts, conversation metadata, or analytics values.
- Do not inspect local Codex session or rollout logs.
- Do not scrape HTML or embed a web view.
- Do not infer lifetime totals, streaks, plugin counts, skill counts, or plan allowances when the endpoint does not provide them.
- Do not restore update checking or downloading.

## Verification

- Red/green tests for query construction, authenticated same-host requests, aggregation, malformed/negative data, best-effort analytics failure, and compact menu presentation.
- `./scripts/check_contracts.sh`
- `swift test`
- `./scripts/verify.sh`
- `./scripts/release.sh`
- Inspect generated 16 px, 64 px, and 1024 px icon representations.
- Install `/Applications/Codex Watch.app`, ensure the prior CodexNotch process is stopped and app is recoverably moved aside, launch the new app, and verify its bundle name, version, identifier, executable, signature, and running process.
