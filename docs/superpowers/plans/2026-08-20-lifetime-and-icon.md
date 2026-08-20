# Codex Watch Lifetime and Icon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship Codex Watch 1.2 with exact first-party lifetime metrics, a profile-style Lifetime dashboard, a visible status icon, a shorter Spark-free menu, and fully verified macOS app-icon sizes.

**Architecture:** Extend the existing same-host bounded client with one independently decoded profile request and store the result beside the bounded analytics dataset in `UsageSnapshot`. Keep range projections unchanged and add a separate dashboard surface for profile semantics. Render the small status mark deterministically in AppKit and continue deriving the ICNS from the existing approved 1024-class source asset.

**Tech Stack:** Swift 6, AppKit, SwiftUI, Foundation `URLSession`, XCTest, shell packaging scripts.

**Spec:** `docs/superpowers/specs/2026-08-20-lifetime-and-icon-design.md`

## Global Constraints

- Work directly on `main`; do not create a branch.
- Use only `https://chatgpt.com` through the existing same-host redirect guard and ephemeral session.
- Keep all authenticated responses in memory and below the one-mebibyte decoder ceiling.
- Do not scan Codex sessions, prompts, rollout logs, browser cookies, or local history.
- Preserve the existing 7/30/90/365 projections, weekly status percentage, CSV behavior, and analytics cadence.
- Version must be 1.2.0 and build must be 17.
- Add regression tests before production changes and observe the expected RED failure for each task.

---

### Task 1: Contract and release metadata

**Files:**
- Modify: `docs/contracts/behavior-contracts.yaml`
- Create: `docs/decisions/009-profile-lifetime-and-icon.md`
- Modify: `AGENTS.md`
- Modify: `Resources/Info.plist`
- Modify: `scripts/verify_app.sh`

**Interfaces:**
- Consumes: active contract IDs `DASHBOARD-SURFACE-011`, `PRIVACY-BOUNDARY-003`, `USAGE-ANALYTICS-012`, and `REFRESH-COORDINATION-013`.
- Produces: active contract `PROFILE-LIFETIME-014` and package metadata 1.2.0 (17).

- [ ] **Step 1: Add the active profile-lifetime contract and ADR**

Define the exact `/backend-api/wham/profiles/me` fields, independent failure, in-memory boundary, Lifetime-tab semantics, Spark presentation filter, and non-template status-icon behavior from the approved spec. Supersede only the surface portions that become outdated; do not alter weekly quota meaning.

- [ ] **Step 2: Update package metadata and verification expectations**

Set `CFBundleShortVersionString` to `1.2.0`, `CFBundleVersion` to `17`, and update `verify_app.sh` to expect them.

- [ ] **Step 3: Validate contracts**

Run: `./scripts/check_contracts.sh`

Expected: PASS with all active contracts structurally valid.

- [ ] **Step 4: Commit**

```sh
git add AGENTS.md Resources/Info.plist docs/contracts/behavior-contracts.yaml docs/decisions/009-profile-lifetime-and-icon.md scripts/verify_app.sh
git commit -m "docs: define Codex Watch 1.2 contracts"
```

### Task 2: Decode and fetch exact profile statistics

**Files:**
- Create: `Sources/CodexWatch/Models/CodexProfileStats.swift`
- Create: `Sources/CodexWatch/Usage/CodexProfileResponseDTO.swift`
- Modify: `Sources/CodexWatch/Usage/CodexUsageClient.swift`
- Modify: `Sources/CodexWatch/Models/UsageSnapshot.swift`
- Create: `Tests/CodexWatchTests/CodexProfileStatsTests.swift`
- Modify: `Tests/CodexWatchTests/CodexUsageClientTests.swift`
- Create: `Tests/CodexWatchTests/Fixtures/profile-stats-complete.json`
- Create: `Tests/CodexWatchTests/Fixtures/profile-stats-partial.json`

**Interfaces:**
- Produces: `CodexProfileStats`, `CodexProfileDailyBucket`, `CodexProfileInvocation`, `CodexUsageClient.fetchProfileStats(referenceDate:)`, and `UsageSnapshot.profileStats`.
- Consumes: `CodexUsageClient.fetchData(from:timeoutInterval:)`, same-host validation, and existing credentials.

- [ ] **Step 1: Write DTO behavior tests**

Add literal fixture assertions for lifetime tokens, peak tokens, longest turn seconds, streaks, unique sorted daily buckets, optional insights, invocations, and `fetchedAt`. Add malformed cases proving negative tokens, duplicate dates, invalid dates, and integer overflow fail closed without fabricating values.

- [ ] **Step 2: Run the focused DTO tests and observe RED**

Run: `swift test --filter CodexProfileStatsTests`

Expected: compilation failure because `CodexProfileStats` and `CodexProfileResponseDTO` do not exist.

- [ ] **Step 3: Implement the profile model and decoder**

Use optional independently validated scalar fields. Parse `start_date` with a POSIX Gregorian calendar, reject duplicate daily dates, ignore malformed optional insights and invocations individually, and sort accepted buckets by date and invocations by descending run count then display name.

- [ ] **Step 4: Run the focused DTO tests and observe GREEN**

Run: `swift test --filter CodexProfileStatsTests`

Expected: PASS.

- [ ] **Step 5: Write client request and preservation tests**

Assert a GET to `/backend-api/wham/profiles/me` with `Accept`, bearer, and `ChatGPT-Account-Id`; assert cross-host rejection, oversized response rejection, successful attachment to a snapshot, and preservation of a previous profile when a new result is nil.

- [ ] **Step 6: Run the focused client tests and observe RED**

Run: `swift test --filter CodexUsageClientTests`

Expected: failures because the profile endpoint and fetch method are missing.

- [ ] **Step 7: Implement the client request and snapshot attachment**

Add `profilePath`, a derived same-origin `profileEndpoint`, `fetchProfileStats(referenceDate:)`, and `UsageSnapshot.adding(profileStats:)`. Reuse the bounded `fetchData` implementation without logging a response.

- [ ] **Step 8: Run profile and client tests and observe GREEN**

Run: `swift test --filter 'CodexProfileStatsTests|CodexUsageClientTests'`

Expected: PASS.

- [ ] **Step 9: Commit**

```sh
git add Sources/CodexWatch/Models/CodexProfileStats.swift Sources/CodexWatch/Models/UsageSnapshot.swift Sources/CodexWatch/Usage/CodexProfileResponseDTO.swift Sources/CodexWatch/Usage/CodexUsageClient.swift Tests/CodexWatchTests/CodexProfileStatsTests.swift Tests/CodexWatchTests/CodexUsageClientTests.swift Tests/CodexWatchTests/Fixtures/profile-stats-complete.json Tests/CodexWatchTests/Fixtures/profile-stats-partial.json
git commit -m "feat: fetch exact Codex profile statistics"
```

### Task 3: Coordinate profile refresh independently

**Files:**
- Modify: `Sources/CodexWatch/App/MenuBarController.swift`
- Modify: `Sources/CodexWatch/App/RefreshCoordinator.swift`
- Modify: `Tests/CodexWatchTests/RefreshCoordinatorTests.swift`
- Modify: `Tests/CodexWatchTests/CodexUsageClientTests.swift`

**Interfaces:**
- Consumes: `CodexUsageClient.fetchProfileStats(referenceDate:)`, `RefreshRequest.fetchAnalytics`, and `UsageSnapshot.adding(profileStats:)`.
- Produces: profile refresh at the existing analytics cadence with last-good in-memory preservation and stale publication.

- [ ] **Step 1: Write refresh outcome tests**

Cover: analytics-eligible refresh fetches quota, aggregate analytics, and profile; quota-only menu-open refresh skips aggregate and profile; profile failure preserves the prior profile while setting stale; a profile success publishes only from the newest generation.

- [ ] **Step 2: Run refresh tests and observe RED**

Run: `swift test --filter RefreshCoordinatorTests`

Expected: assertion failure because profile state is not part of refresh publication.

- [ ] **Step 3: Implement independent profile refresh**

Fetch profile stats only inside the existing analytics-eligible branch. Preserve quota and each last-good analytics capability independently. Keep automatic attempt timing unchanged.

- [ ] **Step 4: Run refresh tests and observe GREEN**

Run: `swift test --filter RefreshCoordinatorTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```sh
git add Sources/CodexWatch/App/MenuBarController.swift Sources/CodexWatch/App/RefreshCoordinator.swift Tests/CodexWatchTests/RefreshCoordinatorTests.swift Tests/CodexWatchTests/CodexUsageClientTests.swift
git commit -m "feat: coordinate lifetime profile refresh"
```

### Task 4: Fix status visibility and hide Spark windows

**Files:**
- Modify: `Sources/CodexWatch/App/MenuBarPresentation.swift`
- Modify: `Tests/CodexWatchTests/MenuBarTextTests.swift`

**Interfaces:**
- Produces: `MenuBarButtonStyle.makeStatusImage()` returning a non-template multicolor `NSImage`, and a quota presentation that filters exactly `codex-spark` and `codex-spark-weekly`.
- Preserves: all underlying additional-window parsing and all non-Spark additional/code-review presentation.

- [ ] **Step 1: Write failing icon and filter tests**

Assert the status image exists at the intended logical size, is non-template, has nonempty TIFF data, and carries the accessibility description. Assert Spark IDs do not appear in `quotaWindows`, while an unknown additional limit and a code-review limit still appear.

- [ ] **Step 2: Run menu tests and observe RED**

Run: `swift test --filter MenuBarTextTests`

Expected: failures because the current image is a template `chart.pie.fill` and Spark windows are present.

- [ ] **Step 3: Implement the status mark and presentation filter**

Draw the cyan arc, dark keyline, and white terminal chevron into a high-resolution AppKit image, set `isTemplate = false`, and assign it in `apply(to:)`. Filter the two stable Spark IDs in `makeQuotaWindows` without changing `UsageSnapshot.additionalWindows`.

- [ ] **Step 4: Run menu tests and observe GREEN**

Run: `swift test --filter MenuBarTextTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```sh
git add Sources/CodexWatch/App/MenuBarPresentation.swift Tests/CodexWatchTests/MenuBarTextTests.swift
git commit -m "fix: improve status icon contrast and hide Spark limits"
```

### Task 5: Add the Profile-style Lifetime dashboard

**Files:**
- Create: `Sources/CodexWatch/App/LifetimeDashboardView.swift`
- Create: `Sources/CodexWatch/App/LifetimeDashboardModel.swift`
- Modify: `Sources/CodexWatch/App/AnalyticsDashboardView.swift`
- Modify: `Sources/CodexWatch/App/AnalyticsDashboardModel.swift`
- Modify: `Sources/CodexWatch/App/AnalyticsWindowController.swift`
- Modify: `Tests/CodexWatchTests/AnalyticsDashboardModelTests.swift`
- Create: `Tests/CodexWatchTests/LifetimeDashboardModelTests.swift`

**Interfaces:**
- Produces: `AnalyticsDashboardSection` with `usage` and `lifetime`, `LifetimeDashboardModel`, and an accessible Lifetime SwiftUI view.
- Consumes: `CodexProfileStats` and existing compact number/date formatting.

- [ ] **Step 1: Write failing Lifetime model tests**

Assert the default top-level section is Usage, the selection persists, five metrics format to `30.3B`, `1.1B`, `15h 43m`, `42 days`, and `82 days`, missing metrics display `Unavailable`, daily buckets remain server-valued and date-sorted, and stale/unavailable states are distinct.

- [ ] **Step 2: Run dashboard model tests and observe RED**

Run: `swift test --filter 'LifetimeDashboardModelTests|AnalyticsDashboardModelTests'`

Expected: compilation failure because the section and Lifetime model do not exist.

- [ ] **Step 3: Implement dashboard state and formatting**

Add the persisted top-level section, a model that maps only validated profile fields to presentation values, heatmap cells, insights, and invocation rows, plus shared compact and duration formatters with literal behavior from the tests.

- [ ] **Step 4: Run model tests and observe GREEN**

Run: `swift test --filter 'LifetimeDashboardModelTests|AnalyticsDashboardModelTests'`

Expected: PASS.

- [ ] **Step 5: Implement the Lifetime SwiftUI surface**

Add the two-section segmented control. Keep all existing Usage content and export behavior under Usage. Build the Lifetime cards, responsive calendar heatmap, insights, invocations, unavailable state, stale badge, and data-through footer without remote images or a Lifetime export action.

- [ ] **Step 6: Build and run all tests**

Run: `swift test`

Expected: all tests PASS with no compiler warnings.

- [ ] **Step 7: Commit**

```sh
git add Sources/CodexWatch/App/AnalyticsDashboardModel.swift Sources/CodexWatch/App/AnalyticsDashboardView.swift Sources/CodexWatch/App/AnalyticsWindowController.swift Sources/CodexWatch/App/LifetimeDashboardModel.swift Sources/CodexWatch/App/LifetimeDashboardView.swift Tests/CodexWatchTests/AnalyticsDashboardModelTests.swift Tests/CodexWatchTests/LifetimeDashboardModelTests.swift
git commit -m "feat: add Codex lifetime dashboard"
```

### Task 6: Verify icon sizes, package, install, and publish

**Files:**
- Modify: `scripts/verify_app.sh`
- Modify if required: `scripts/build_icon.sh`
- Modify: `README.md`

**Interfaces:**
- Consumes: `Resources/AppIcon.png`, release metadata 1.2.0 (17), and the completed application.
- Produces: a verified universal `Codex Watch.app`, local release ZIP/checksum, installed application, and pushed `main` commits.

- [ ] **Step 1: Add executable iconset verification**

After extracting the ICNS, require all ten standard filenames and assert their exact physical dimensions with `sips`: 16, 32, 32, 64, 128, 256, 256, 512, 512, and 1024 pixels.

- [ ] **Step 2: Run bundle verification and observe RED if any representation is wrong**

Run: `./scripts/verify.sh`

Expected: PASS only when every required representation exists at its exact size.

- [ ] **Step 3: Update README behavior and privacy documentation**

Document the Lifetime tab, official profile metrics, Spark menu filtering, same-host profile request, 15-minute analytics/profile cadence, and 1.2.0 build/install behavior.

- [ ] **Step 4: Run final verification**

Run: `swift test`

Run: `./scripts/verify.sh`

Run: `./scripts/release.sh`

Expected: tests, contract validation, universal build, icon extraction, code-sign verification, ZIP creation, and checksum creation all PASS.

- [ ] **Step 5: Inspect, install, and relaunch**

Quit the running Codex Watch process, replace `/Applications/Codex Watch.app` with the verified 1.2.0 bundle while retaining the existing backup, launch it, and verify process identity, bundle version/build, architectures, signature, menu icon visibility, Spark absence, and Lifetime values.

- [ ] **Step 6: Review and commit final documentation or verification changes**

```sh
git add README.md scripts/build_icon.sh scripts/verify_app.sh
git commit -m "build: verify Codex Watch 1.2 icon assets"
```

- [ ] **Step 7: Push main**

Run: `git push origin main`

Expected: `origin/main` advances to the verified local HEAD. Do not create or push a release tag unless separately requested.
