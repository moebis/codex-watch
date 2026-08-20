# Codex Watch

Codex Watch is a small, native macOS menu bar app that shows your remaining weekly ChatGPT Codex quota and recent token usage.

## What it does

- Displays `68%` beside a system icon in the macOS menu bar.
- Shows the server-reported ChatGPT plan in the expanded menu when it is recognized.
- Shows the server-reported ChatGPT credits remaining when the usage response provides a valid value.
- Visualizes the remaining weekly quota and time until weekly reset with two progress bars.
- Shows available rate-limit reset credits and visualizes time remaining until the next expiry when ChatGPT provides exact grant and expiry metadata.
- Shows total, input, cached-input, and output tokens plus turns and chats for the trailing 30 calendar days.
- Refreshes automatically every 60 seconds and supports manual refresh.
- Refreshes analytics at launch, on manual refresh, and at most once every 15 minutes automatically.
- Shows the installed version in the menu.
- Opens the installed ChatGPT/Codex app from the menu.
- Opens the full Codex Usage Analytics dashboard in your default browser.
- Uses no telemetry, automatic updater, embedded browser view, or third-party package.

Codex Watch does not create a notch overlay, inspect conversation logs, read prompts, or store conversation metadata.

## Install

Build the app locally, verify it, and move the resulting `Codex Watch.app` to Applications:

```sh
./scripts/verify.sh /private/tmp/codex-watch-build
ditto "/private/tmp/codex-watch-build/Codex Watch.app" "/Applications/Codex Watch.app"
```

The automated release is ad-hoc signed because this repository does not currently have an Apple Developer ID certificate. macOS may require Control-clicking the app and choosing **Open** on first launch.

## Authentication and privacy

Codex Watch reads `tokens.access_token` and `tokens.account_id` from `CODEX_HOME/auth.json`. When `CODEX_HOME` is not set, it uses `~/.codex/auth.json`.

The token is used only in memory for this read-only request:

```text
GET https://chatgpt.com/backend-api/wham/usage
GET https://chatgpt.com/backend-api/wham/analytics/daily-workspace-usage-counts
```

The analytics request is limited to the trailing 30 days and decodes only daily aggregate token, turn, and thread totals. It is best-effort: a changed or unavailable analytics endpoint never prevents the weekly quota from loading.

The network session is ephemeral, has no response cache or cookie store, and rejects redirects to another host. Tokens, headers, response bodies, and analytics values are never logged or persisted by Codex Watch.

The endpoint is an internal ChatGPT endpoint and may change without notice.
If an endpoint omits or changes a field, the app hides that unavailable detail rather than guessing. Codex Watch does not infer an absolute token allowance, lifetime usage, streaks, or profile statistics.

Each ChatGPT response is limited to one mebibyte before decoding. The app makes no update-check request and never downloads or installs releases.

## Build and test

Requirements: macOS 14 or newer, Xcode 15 or newer, and Swift 5.9 or newer.

```sh
swift test
./scripts/verify.sh
```

Create a local universal release archive:

```sh
ARCHITECTURES="arm64 x86_64" ARCHIVE_ARCH=universal ./scripts/release.sh
```

## Release process

1. Update `CFBundleShortVersionString` in `Resources/Info.plist`.
2. Merge the verified change into `main`.
3. Create an annotated tag matching the app version, such as `v0.2.0`.
4. Push the tag.
5. `.github/workflows/release.yml` builds and verifies a universal app, creates the ZIP and SHA-256 file, and publishes both files to the GitHub Release.

The workflow rejects a tag that does not match the version in `Info.plist`.

## License

MIT License. See [LICENSE](LICENSE).

Codex Watch is derived from [CodexNotch by smallyunet](https://github.com/smallyunet/codex-notch). The original copyright and license notice are preserved.
