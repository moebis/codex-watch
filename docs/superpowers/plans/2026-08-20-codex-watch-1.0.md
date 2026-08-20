# Codex Watch 1.0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Release Codex Watch 1.0 with an original icon and truthful, best-effort 30-day token usage in its macOS menu.

**Architecture:** Extend the existing same-host authenticated client with one narrowly decoded aggregate endpoint and keep the result in `UsageSnapshot` memory. Render the aggregate in a separate native AppKit menu view while retaining the quota controller and 60-second timer. Rename the SwiftPM module, app packaging, documentation, GitHub repository, and local checkout without introducing a compatibility shim or branch.

**Tech Stack:** Swift 5.9, AppKit, Foundation `URLSession`, XCTest, SwiftPM, shell packaging, GitHub CLI, macOS `iconutil`/`codesign`.

**Spec:** `docs/specs/codex-watch-1.0.md`

## Global Constraints

- Work and publish only on `main`; never create a branch.
- User-facing name is `Codex Watch`; code module/executable is `CodexWatch`.
- Version is `1.0.0`, build is `15`, bundle identifier is `com.moebis.codexwatch`.
- Analytics remains same-host HTTPS, read-only, ephemeral, uncached, cookieless, bounded to one mebibyte, and best-effort.
- Never inspect session logs, prompts, cookies, browser storage, or full response bodies.
- Preserve original-project attribution and the MIT license.
- Do not add update checks, downloads, telemetry, dependencies, a web view, or inferred lifetime/profile metrics.

---

### Task 0: Rename SwiftPM targets mechanically

**Files:**
- Rename: `Sources/CodexNotch` to `Sources/CodexWatch`
- Rename: `Tests/CodexNotchTests` to `Tests/CodexWatchTests`
- Rename: `Sources/CodexWatch/App/CodexNotchApp.swift` to `Sources/CodexWatch/App/CodexWatchApp.swift`
- Modify: `Package.swift` and test imports.

**Interfaces:**
- Produces: final `CodexWatch` module paths used by all later test-first tasks.
- Consumes: existing source and test targets without changing runtime behavior.

- [ ] **Step 1: Move target directories and the app entry file**

Use filesystem moves so Git records the existing files as renames.

- [ ] **Step 2: Update the SwiftPM module/product names and imports**

Change `CodexNotch` identifiers to `CodexWatch` only where they name the package, target, executable, app entry enum, or test import.

- [ ] **Step 3: Verify the mechanical rename**

Run: `swift test`

Expected: the existing suite passes before analytics behavior is added.

### Task 1: Define and test 30-day aggregate analytics

**Files:**
- Create: `Sources/CodexWatch/Models/UsageAnalyticsSummary.swift`
- Create: `Sources/CodexWatch/Usage/UsageAnalyticsResponseDTO.swift`
- Create: `Tests/Fixtures/usage-analytics-30-day.json`
- Modify: `Tests/CodexWatchTests/CodexUsageClientTests.swift`

**Interfaces:**
- Produces: `UsageAnalyticsSummary`, `UsageAnalyticsResponseDTO.summary(periodStart:periodEnd:fetchedAt:)`.
- Consumes: server `data[].totals` fields documented in the spec.

- [ ] **Step 1: Write failing aggregation tests**

Add tests with literal expected totals for all six metrics, plus rejection of negative or incomplete day totals.

- [ ] **Step 2: Run the focused tests and verify RED**

Run: `swift test --filter CodexUsageClientTests`

Expected: compilation fails because the analytics DTO and summary do not exist.

- [ ] **Step 3: Implement the minimal DTO and summary model**

Decode snake-case fields into `Int64`, require a nonempty series with complete nonnegative values, and use overflow-reporting addition so invalid aggregates return `nil`.

- [ ] **Step 4: Run the focused tests and verify GREEN**

Run: `swift test --filter CodexUsageClientTests`

Expected: all focused tests pass.

### Task 2: Fetch analytics safely and preserve quota on failure

**Files:**
- Modify: `Sources/CodexWatch/Usage/CodexUsageClient.swift`
- Modify: `Sources/CodexWatch/Models/UsageSnapshot.swift`
- Modify: `Tests/CodexWatchTests/CodexUsageClientTests.swift`

**Interfaces:**
- Produces: `CodexUsageClient.fetchAnalytics(referenceDate:calendar:) async throws -> UsageAnalyticsSummary` and `UsageSnapshot.adding(analytics:)`.
- Consumes: the existing credentials, session, host restriction, response-size cap, and endpoint base URL.

- [ ] **Step 1: Write failing request-boundary tests**

Test the exact analytics path/query, authorization/account headers, inclusive trailing 30-day range, another-host rejection, and oversized-response rejection. Test that a failed analytics request can leave a valid quota snapshot unchanged.

- [ ] **Step 2: Run the focused tests and verify RED**

Run: `swift test --filter CodexUsageClientTests`

Expected: failures because `fetchAnalytics` and snapshot merging are absent.

- [ ] **Step 3: Implement the minimal client method**

Build the endpoint with `URLComponents`, reuse `fetchData`, decode only the aggregate DTO, and attach successful analytics without changing `fetch()` quota behavior.

- [ ] **Step 4: Run the focused tests and verify GREEN**

Run: `swift test --filter CodexUsageClientTests`

Expected: all focused tests pass.

### Task 3: Present analytics and schedule bounded refreshes

**Files:**
- Create: `Sources/CodexWatch/App/UsageAnalyticsMenuView.swift`
- Modify: `Sources/CodexWatch/App/MenuBarController.swift`
- Modify: `Tests/CodexWatchTests/MenuBarTextTests.swift`

**Interfaces:**
- Produces: `UsageAnalyticsPresentation`, `UsageAnalyticsMenuView`, a 15-minute analytics refresh gate, and `Open Usage Analytics…`.
- Consumes: `UsageSnapshot.analytics` and the existing 60-second quota refresh.

- [ ] **Step 1: Write failing presentation tests**

Test compact numeric formatting, six labeled rows, unavailable analytics omission, the official analytics action title, and retention of the no-update menu contract.

- [ ] **Step 2: Run the focused tests and verify RED**

Run: `swift test --filter MenuBarTextTests`

Expected: compilation or assertion failures because the analytics view/presentation is absent.

- [ ] **Step 3: Implement the menu view and refresh gate**

Fetch analytics at launch/manual refresh and at most every 15 minutes automatically, retain the last successful in-memory summary, insert the native details card only when available, and open the exact official dashboard URL through `NSWorkspace`.

- [ ] **Step 4: Run the focused tests and verify GREEN**

Run: `swift test --filter MenuBarTextTests`

Expected: all focused tests pass.

### Task 4: Rename the product and integrate the generated icon

**Files:**
- Create: `Resources/AppIcon.png`
- Delete: `Resources/AppIcon.svg`
- Modify: `Package.swift`, `Resources/Info.plist`, scripts, workflows, tests, source identity strings, `AGENTS.md`, contracts, decisions, and `README.md`.

**Interfaces:**
- Produces: `CodexWatch` module/executable, `Codex Watch.app`, `CodexWatch.icns`, bundle id `com.moebis.codexwatch`, version `1.0.0` build `15`.
- Consumes: generated PNG at `/Users/moebis/.codex/generated_images/01a01de4-076e-7710-b117-2b61bc549e4f/exec-68299f6c-67d6-4082-b45a-cbd07c1be424.png`.

- [ ] **Step 1: Complete user-facing identity changes**

Update the final app display name, executable packaging, bundle identifier, version, scripts, workflow artifact names, and source identity strings.

- [ ] **Step 2: Integrate the generated icon**

Copy the generated project-bound PNG to `Resources/AppIcon.png`, update icon build/verification to produce `CodexWatch.icns`, and remove the superseded SVG.

- [ ] **Step 3: Update product metadata and attribution**

Set all final identity/version values, update build/release paths and workflow titles, preserve the license, credit `https://github.com/smallyunet/codex-notch`, and document the analytics endpoint/privacy behavior.

- [ ] **Step 4: Update active contracts and architecture decision**

Record the same-host aggregate endpoint, 15-minute refresh ceiling, best-effort behavior, no persistence/log scanning, and Codex Watch packaging guards.

### Task 5: Verify, publish, rename, and install

**Files:**
- All intended paths from Tasks 1–4.

**Interfaces:**
- Produces: verified public `moebis/codex-watch` main, renamed local checkout, and running `/Applications/Codex Watch.app`.

- [ ] **Step 1: Run contract and unit verification**

Run: `./scripts/check_contracts.sh && swift test`

Expected: zero failures.

- [ ] **Step 2: Run bundle and release verification**

Run: `./scripts/verify.sh /private/tmp/codex-watch-build && ./scripts/release.sh /private/tmp/codex-watch-release`

Expected: both commands exit zero and produce verified `Codex Watch.app` plus archive/checksum.

- [ ] **Step 3: Inspect icon representations and intended diff**

Extract and inspect 16 px, 64 px, and 1024 px icons; run `git status`, `git diff --check`, and review the full diff. Stage only intended paths.

- [ ] **Step 4: Commit and push main**

Commit the verified scope, push `main`, and confirm local/remote commit identity.

- [ ] **Step 5: Rename GitHub repository and local checkout**

Rename the public repository to `moebis/codex-watch`, update `origin`, preserve `upstream`, and move the checkout to `/Users/moebis/Documents/Codex/Codex Watch`.

- [ ] **Step 6: Replace and relaunch the installed app**

Stop the old app, move `/Applications/CodexNotch.app` recoverably to the Trash if present, install the verified `Codex Watch.app`, launch it, and verify bundle metadata, signature, executable, and process.
