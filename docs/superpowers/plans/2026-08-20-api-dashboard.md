# Codex Watch 1.1 API Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship Codex Watch 1.1 with a native Codex analytics dashboard, complete same-host quota capabilities, truthful 7/30/90/365-day projections, deterministic pace, CSV export, and non-overlapping refresh behavior.

**Architecture:** Keep one Codex-specific executable and separate decoding, immutable domain state, projection, refresh coordination, and presentation. Fetch one bounded 365-day analytics dataset, derive selected ranges in memory, keep all authenticated response data process-local, and expose a reusable on-demand dashboard without changing the base weekly menu-bar percentage.

**Tech Stack:** Swift 5.9, AppKit, SwiftUI, Apple Charts, Foundation `URLSession`, XCTest, shell verification scripts.

**Spec:** `docs/superpowers/specs/2026-08-20-api-dashboard-design.md`

## Global Constraints

- Target macOS 14 or newer and keep `LSUIElement=true`; no persistent Dock icon.
- Work directly on `main`; never create a branch or pull request.
- Preserve the base weekly remaining percentage as the sole menu-bar number.
- Send credentials only to HTTPS on the original ChatGPT host and port through the existing ephemeral session.
- Limit every response to 1,048,576 bytes and reject cross-host redirects.
- Keep authenticated response data in memory; persist only preferences/window placement and user-requested CSV output.
- Do not read Codex sessions, the Codex thread database, prompts, browser cookies, process lists, or Keychain browser material.
- Add no updater, telemetry, automatic download, third-party package, or new network host.
- Use strict red-green-refactor for every production behavior and stage only the listed paths.
- Release as version `1.1.0`, build `16`.

---

## File structure

### Domain and usage

- `Sources/CodexWatch/Models/UsageSnapshot.swift` — base/named quota windows, full reset-credit inventory, optional code-review and spend-control summaries.
- `Sources/CodexWatch/Models/UsageAnalyticsDataset.swift` — immutable validated daily analytics domain values and completeness metadata.
- `Sources/CodexWatch/Models/UsageAnalyticsProjection.swift` — selected-range totals, comparison, coverage, chart cells, and aggregated model/client rows.
- `Sources/CodexWatch/Models/UsagePace.swift` — pure current-window pace calculation.
- `Sources/CodexWatch/Usage/UsageResponseDTO.swift` — lossy optional capability decoding and snapshot mapping.
- `Sources/CodexWatch/Usage/UsageAnalyticsResponseDTO.swift` — 365-day response validation and dataset construction.
- `Sources/CodexWatch/Usage/CodexUsageClient.swift` — bounded 365-day analytics request and full reset-credit enrichment.

### Refresh and presentation

- `Sources/CodexWatch/App/RefreshPolicy.swift` — fixed/adaptive preferences and pure next-delay/freshness decisions.
- `Sources/CodexWatch/App/RefreshCoordinator.swift` — trigger coalescing, generation ownership, cancellation, scheduling, and publication.
- `Sources/CodexWatch/App/MenuBarController.swift` — menu binding and dashboard ownership only.
- `Sources/CodexWatch/App/MenuBarPresentation.swift` — extracted menu text/progress presentation types from `MenuBarController.swift`.
- `Sources/CodexWatch/App/AnalyticsDashboardModel.swift` — selected range, current dataset/projection, stale/error state, and export action.
- `Sources/CodexWatch/App/AnalyticsDashboardView.swift` — SwiftUI/Charts dashboard.
- `Sources/CodexWatch/App/AnalyticsWindowController.swift` — one reusable native window and save panel.
- `Sources/CodexWatch/Export/UsageAnalyticsCSVExporter.swift` — deterministic RFC 4180 CSV serialization.

### Tests and fixtures

- `Tests/CodexWatchTests/UsageCapabilityTests.swift`
- `Tests/CodexWatchTests/UsageAnalyticsDatasetTests.swift`
- `Tests/CodexWatchTests/UsageAnalyticsProjectionTests.swift`
- `Tests/CodexWatchTests/UsagePaceTests.swift`
- `Tests/CodexWatchTests/RefreshCoordinatorTests.swift`
- `Tests/CodexWatchTests/UsageAnalyticsCSVExporterTests.swift`
- `Tests/CodexWatchTests/AnalyticsDashboardModelTests.swift`
- `Tests/Fixtures/usage-additional-limits.json`
- `Tests/Fixtures/usage-analytics-365-partial.json`

---

### Task 1: Model and decode every trustworthy quota capability

**Files:**
- Create: `Tests/CodexWatchTests/UsageCapabilityTests.swift`
- Create: `Tests/Fixtures/usage-additional-limits.json`
- Modify: `Sources/CodexWatch/Models/UsageSnapshot.swift`
- Modify: `Sources/CodexWatch/Usage/UsageResponseDTO.swift`
- Modify: `Sources/CodexWatch/Usage/CodexUsageClient.swift`
- Modify: `Tests/CodexWatchTests/CodexUsageClientTests.swift`

**Interfaces:**
- Produces `NamedUsageWindow(id:title:window:)`, `ResetCredit`, `SpendControlSummary`, `UsageSnapshot.additionalWindows`, `UsageSnapshot.codeReviewWindows`, `UsageSnapshot.resetCredits`, and `UsageSnapshot.spendControl`.
- Preserves `UsageSnapshot.weeklyWindow` as a lookup only in `windows`, never in `additionalWindows`.

- [ ] **Step 1: Add the failing quota-capability fixture and tests**

Create a fixture containing a base weekly window, a valid Spark five-hour/weekly entry, a malformed extra entry, full reset-credit metadata, a recognized code-review rate-limit shape, and a complete spend-control limit. Add tests with literal expectations:

```swift
func testAdditionalLimitsDoNotReplaceBaseWeeklyQuota() throws {
    let data = try Data(contentsOf: fixtureURL("usage-additional-limits.json"))
    let snapshot = try JSONDecoder().decode(UsageResponseDTO.self, from: data).snapshot(
        fetchedAt: Date(timeIntervalSince1970: 2_000_000_000)
    )

    XCTAssertEqual(snapshot.weeklyWindow?.id, "primary")
    XCTAssertEqual(snapshot.weeklyWindow?.remainingPercent, 68)
    XCTAssertEqual(snapshot.additionalWindows.map(\.id), ["codex-spark", "codex-spark-weekly"])
    XCTAssertEqual(snapshot.additionalWindows.map(\.title), [
        "Codex Spark 5-hour",
        "Codex Spark Weekly"
    ])
    XCTAssertEqual(snapshot.additionalWindows.map(\.window.kind), [.rolling(hours: 5), .weekly])
}

func testMalformedOptionalCapabilityPreservesValidSiblings() throws {
    let data = try Data(contentsOf: fixtureURL("usage-additional-limits.json"))
    let snapshot = try JSONDecoder().decode(UsageResponseDTO.self, from: data).snapshot()

    XCTAssertEqual(snapshot.windows.count, 1)
    XCTAssertEqual(snapshot.additionalWindows.count, 2)
    XCTAssertEqual(snapshot.resetCredits.count, 2)
    XCTAssertNotNil(snapshot.spendControl)
}

func testMenuBarTitleStillUsesBaseWeeklyWindow() throws {
    let data = try Data(contentsOf: fixtureURL("usage-additional-limits.json"))
    let snapshot = try JSONDecoder().decode(UsageResponseDTO.self, from: data).snapshot()

    XCTAssertEqual(MenuBarText.statusTitle(snapshot: snapshot), "68%")
}
```

- [ ] **Step 2: Run the focused tests and confirm RED**

Run:

```bash
swift test --filter UsageCapabilityTests
```

Expected: compilation fails because `additionalWindows`, `resetCredits`, `spendControl`, and `NamedUsageWindow` do not exist.

- [ ] **Step 3: Implement the minimal domain and lossy decoding**

Add these public-in-module shapes and map optional entries independently:

```swift
struct NamedUsageWindow: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let window: UsageWindow
}

struct ResetCredit: Equatable, Identifiable, Sendable {
    let id: String
    let status: String
    let title: String?
    let grantedAt: Date?
    let expiresAt: Date?
    let isSupportedByPlan: Bool?
}

struct SpendControlSummary: Equatable, Sendable {
    let limit: Decimal
    let used: Decimal
    let remainingPercent: Double?
    let resetsAt: Date?
}
```

Decode `additional_rate_limits` through a private lossy element wrapper. Use `codex-spark` and `codex-spark-weekly` for any entry whose name or metered feature contains `spark`; otherwise use a 64-character lowercase alphanumeric slug. Require finite percentages and positive durations before constructing a window. Keep malformed optional capabilities out of the snapshot without throwing away the base response.

Change reset-credit enrichment from an earliest-only `ResetCreditDetails` to a validated array. Derive the existing `availableResetCredits`, `nextResetCreditGrantedAt`, and `nextResetCreditExpiry` compatibility accessors from that array so existing presentation tests remain valid.

- [ ] **Step 4: Run quota tests and the existing client/menu tests**

Run:

```bash
swift test --filter UsageCapabilityTests
swift test --filter CodexUsageClientTests
swift test --filter MenuBarTextTests
```

Expected: all selected tests pass with the original weekly title unchanged.

- [ ] **Step 5: Commit the quota capability slice**

```bash
git add -- Sources/CodexWatch/Models/UsageSnapshot.swift Sources/CodexWatch/Usage/UsageResponseDTO.swift Sources/CodexWatch/Usage/CodexUsageClient.swift Tests/CodexWatchTests/UsageCapabilityTests.swift Tests/CodexWatchTests/CodexUsageClientTests.swift Tests/Fixtures/usage-additional-limits.json
git diff --cached --check
git commit -m "feat: expose all Codex quota windows"
```

---

### Task 2: Add a validated 365-day dataset without breaking the current menu

**Files:**
- Create: `Sources/CodexWatch/Models/UsageAnalyticsDataset.swift`
- Create: `Tests/CodexWatchTests/UsageAnalyticsDatasetTests.swift`
- Create: `Tests/Fixtures/usage-analytics-365-partial.json`
- Modify: `Sources/CodexWatch/Usage/UsageAnalyticsResponseDTO.swift`
- Modify: `Sources/CodexWatch/Usage/CodexUsageClient.swift`
- Modify: `Tests/CodexWatchTests/CodexUsageClientTests.swift`

**Interfaces:**
- Adds `UsageAnalyticsDataset` beside the existing 30-day summary so this task remains independently buildable.
- Produces `UsageAnalyticsDay`, `UsageTokenTotals`, `UsageModelActivity`, and `UsageClientActivity`.
- `CodexUsageClient.fetchAnalyticsDataset(referenceDate:calendar:) async throws -> UsageAnalyticsDataset` requests 365 inclusive days.
- Keeps the existing `fetchAnalytics(...) -> UsageAnalyticsSummary` adapter unchanged until Task 3 switches every consumer atomically.

- [ ] **Step 1: Add failing dataset validation tests**

```swift
func testDatasetPreservesObservedDatesAndPartialBreakdowns() throws {
    let data = try Data(contentsOf: fixtureURL("usage-analytics-365-partial.json"))
    let calendar = utcCalendar()
    let start = calendar.date(from: DateComponents(year: 2025, month: 8, day: 21))!
    let end = calendar.date(from: DateComponents(year: 2026, month: 8, day: 20))!
    let fetchedAt = calendar.date(from: DateComponents(year: 2026, month: 8, day: 20))!

    let dataset = try XCTUnwrap(
        JSONDecoder().decode(UsageAnalyticsResponseDTO.self, from: data).dataset(
            requestedStart: start,
            requestedEnd: end,
            calendar: calendar,
            fetchedAt: fetchedAt
        )
    )

    XCTAssertEqual(dataset.days.map(\.date), [
        calendar.date(from: DateComponents(year: 2026, month: 8, day: 18))!,
        calendar.date(from: DateComponents(year: 2026, month: 8, day: 19))!
    ])
    XCTAssertEqual(dataset.dataThrough, calendar.date(from: DateComponents(year: 2026, month: 8, day: 19)))
    XCTAssertTrue(dataset.modelBreakdownIsPartial)
    XCTAssertFalse(dataset.clientBreakdownIsPartial)
    XCTAssertEqual(dataset.days[0].models.map(\.model), ["gpt-5.6-sol"])
}

func testDuplicateOrInvalidDailyRowsRejectWholeDataset() throws {
    let response = try JSONDecoder().decode(
        UsageAnalyticsResponseDTO.self,
        from: Data(#"{"group_by":"day","data":[{"date":"2026-08-19","totals":{"threads":1,"turns":1,"uncached_text_input_tokens":1,"cached_text_input_tokens":1,"text_output_tokens":1,"text_total_tokens":3}},{"date":"2026-08-19","totals":{"threads":1,"turns":1,"uncached_text_input_tokens":1,"cached_text_input_tokens":1,"text_output_tokens":1,"text_total_tokens":3}}]}"#.utf8)
    )

    XCTAssertNil(response.dataset(
        requestedStart: day("2026-08-01"),
        requestedEnd: day("2026-08-20"),
        calendar: utcCalendar()
    ))
}
```

Add a request-boundary test for `fetchAnalyticsDataset` that expects `start_date=2025-08-21`, `end_date=2026-08-20`, and a dataset. Keep the existing 30-day `fetchAnalytics` boundary test green until Task 3 removes that compatibility path.

- [ ] **Step 2: Run dataset/client tests and confirm RED**

```bash
swift test --filter UsageAnalyticsDatasetTests
swift test --filter CodexUsageClientTests/testAnalyticsRequestUsesTrailingThreeHundredSixtyFiveDaysAndExistingCredentialBoundary
```

Expected: compilation fails because `UsageAnalyticsDataset` and `dataset(requestedStart:requestedEnd:calendar:fetchedAt:)` do not exist.

- [ ] **Step 3: Implement dataset types, bounded nested values, and 365-day request**

Use these immutable contracts:

```swift
struct UsageAnalyticsDataset: Equatable, Sendable {
    let requestedStart: Date
    let requestedEnd: Date
    let days: [UsageAnalyticsDay]
    let fetchedAt: Date
    let modelBreakdownIsPartial: Bool
    let clientBreakdownIsPartial: Bool

    var dataThrough: Date? { days.last?.date }
}

struct UsageAnalyticsDay: Equatable, Sendable {
    let date: Date
    let totals: UsageTokenTotals
    let models: [UsageModelActivity]
    let clients: [UsageClientActivity]
}
```

Require complete nonnegative daily totals. Decode model/client elements through lossy wrappers; skip invalid elements and set the relevant partial flag. Cap identifiers to 128 UTF-8 bytes. Use checked `Int64` addition only in projections, not during decoding. Add `fetchAnalyticsDataset` with a `-364` day start offset while retaining the same endpoint, query keys, timeout, host guard, and response limit. Leave the old 30-day `fetchAnalytics` method in place only as a temporary compatibility adapter for the existing menu.

- [ ] **Step 4: Run the focused and complete unit suites**

```bash
swift test --filter UsageAnalyticsDatasetTests
swift test --filter CodexUsageClientTests
swift test
```

Expected: all tests pass; the new dataset test proves the 365-day boundary while the temporary 30-day compatibility test still protects the current menu.

- [ ] **Step 5: Commit the dataset slice**

```bash
git add -- Sources/CodexWatch/Models/UsageAnalyticsDataset.swift Sources/CodexWatch/Usage/UsageAnalyticsResponseDTO.swift Sources/CodexWatch/Usage/CodexUsageClient.swift Tests/CodexWatchTests/UsageAnalyticsDatasetTests.swift Tests/CodexWatchTests/CodexUsageClientTests.swift Tests/Fixtures/usage-analytics-365-partial.json
git diff --cached --check
git commit -m "feat: load bounded Codex analytics history"
```

---

### Task 3: Derive truthful range projections, coverage, and comparisons

**Files:**
- Create: `Sources/CodexWatch/Models/UsageAnalyticsProjection.swift`
- Create: `Tests/CodexWatchTests/UsageAnalyticsProjectionTests.swift`
- Delete: `Sources/CodexWatch/Models/UsageAnalyticsSummary.swift`
- Modify: `Sources/CodexWatch/Models/UsageSnapshot.swift`
- Modify: `Sources/CodexWatch/Usage/CodexUsageClient.swift`
- Modify: `Sources/CodexWatch/App/MenuBarController.swift`
- Modify: `Sources/CodexWatch/App/UsageAnalyticsMenuView.swift`
- Modify: `Tests/CodexWatchTests/CodexUsageClientTests.swift`
- Modify: `Tests/CodexWatchTests/MenuBarTextTests.swift`

**Interfaces:**
- Produces `AnalyticsRange`, `UsageAnalyticsProjection`, `UsageDayCell`, `UsageModelRow`, `UsageClientRow`, and `UsageComparison`.
- `UsageAnalyticsProjection.make(dataset:range:referenceDate:calendar:) -> UsageAnalyticsProjection?` is the sole aggregation entry point for menu, dashboard, and CSV.
- Changes `UsageSnapshot.analytics` to `analyticsDataset: UsageAnalyticsDataset?`, switches the controller to `fetchAnalyticsDataset`, and removes the temporary summary method and type in the same commit.

- [ ] **Step 1: Write failing literal projection tests**

```swift
func testThirtyDayProjectionReportsCoverageAndDataThrough() throws {
    let dataset = makeDataset(
        requestedStart: day("2025-08-21"),
        requestedEnd: day("2026-08-20"),
        observed: [
            makeDay("2026-08-18", total: 10, turns: 2, chats: 1),
            makeDay("2026-08-19", total: 20, turns: 3, chats: 2)
        ]
    )

    let projection = try XCTUnwrap(UsageAnalyticsProjection.make(
        dataset: dataset,
        range: .days30,
        referenceDate: day("2026-08-20"),
        calendar: utcCalendar()
    ))

    XCTAssertEqual(projection.totalTokens, 30)
    XCTAssertEqual(projection.observedDayCount, 2)
    XCTAssertEqual(projection.requestedDayCount, 30)
    XCTAssertEqual(projection.missingDayCount, 28)
    XCTAssertEqual(projection.dataThrough, day("2026-08-19"))
    XCTAssertNil(projection.comparison)
}

func testComparisonRequiresNinetyPercentCoverageInBothPeriods() throws {
    let dataset = makeComparisonDataset(currentTotal: 120, previousTotal: 100, missingCurrentDays: 0)
    let projection = try XCTUnwrap(UsageAnalyticsProjection.make(
        dataset: dataset,
        range: .days7,
        referenceDate: day("2026-08-20"),
        calendar: utcCalendar()
    ))

    XCTAssertEqual(projection.comparison, .percent(0.20))

    let incomplete = makeComparisonDataset(currentTotal: 120, previousTotal: 100, missingCurrentDays: 1)
    XCTAssertNil(UsageAnalyticsProjection.make(
        dataset: incomplete,
        range: .days7,
        referenceDate: day("2026-08-20"),
        calendar: utcCalendar()
    )?.comparison)
}

func testModelsUseTurnsWhileClientsUseTokens() throws {
    let projection = try XCTUnwrap(makeBreakdownProjection())

    XCTAssertEqual(projection.models.first?.model, "gpt-5.6-sol")
    XCTAssertEqual(projection.models.first?.turns, 8)
    XCTAssertEqual(projection.models.first?.turnShare, 0.8)
    XCTAssertEqual(projection.clients.first?.clientID, "CODEX_DESKTOP_APP")
    XCTAssertEqual(projection.clients.first?.totalTokens, 900)
}
```

- [ ] **Step 2: Run projection tests and confirm RED**

```bash
swift test --filter UsageAnalyticsProjectionTests
```

Expected: compilation fails because the projection types do not exist.

- [ ] **Step 3: Implement checked aggregation and missing-day cells**

Define ranges with literal day counts:

```swift
enum AnalyticsRange: Int, CaseIterable, Identifiable, Sendable {
    case days7 = 7
    case days30 = 30
    case days90 = 90
    case days365 = 365

    var id: Int { rawValue }
    var title: String { "\(rawValue)d" }
}
```

Build inclusive current and previous date sets with the supplied calendar. Use `addingReportingOverflow` for every integer aggregate. Emit one `UsageDayCell` per requested date with `.observed(totals)` or `.missing`. Aggregate models by exact normalized model name and clients by exact normalized client ID. Sort models by turns then name; sort clients by total tokens then ID. Permit comparison only for non-365 ranges when each period has `ceil(days * 0.9)` observed dates and the previous total is positive.

After the pure projection is green, atomically change `UsageSnapshot.analytics` to `analyticsDataset`, update `adding(analyticsDataset:)`, switch `MenuBarController` to `fetchAnalyticsDataset`, delete the compatibility `fetchAnalytics` method and `UsageAnalyticsSummary.swift`, and adapt the compact menu card to a `.days30` projection. This is the only dataset cutover, so no intermediate commit references both analytics storage models.

Change the compact menu analytics card to consume `.days30`, display `Data through`, and show `28/30 days` when coverage is incomplete.

- [ ] **Step 4: Run projection and menu tests**

```bash
swift test --filter UsageAnalyticsProjectionTests
swift test --filter MenuBarTextTests
swift test
```

Expected: range totals, missing gaps, model/client semantics, compact copy, and all existing tests pass.

- [ ] **Step 5: Commit projection behavior**

```bash
git add -- Sources/CodexWatch/Models/UsageAnalyticsProjection.swift Sources/CodexWatch/Models/UsageAnalyticsSummary.swift Sources/CodexWatch/Models/UsageSnapshot.swift Sources/CodexWatch/Usage/CodexUsageClient.swift Sources/CodexWatch/App/MenuBarController.swift Sources/CodexWatch/App/UsageAnalyticsMenuView.swift Tests/CodexWatchTests/UsageAnalyticsProjectionTests.swift Tests/CodexWatchTests/CodexUsageClientTests.swift Tests/CodexWatchTests/MenuBarTextTests.swift
git diff --cached --check
git commit -m "feat: project Codex analytics ranges"
```

---

### Task 4: Add deterministic quota pace

**Files:**
- Create: `Sources/CodexWatch/Models/UsagePace.swift`
- Create: `Sources/CodexWatch/App/MenuBarPresentation.swift`
- Create: `Tests/CodexWatchTests/UsagePaceTests.swift`
- Modify: `Sources/CodexWatch/App/MenuBarController.swift`

**Interfaces:**
- Produces `UsagePace(deltaPercent:expectedUsedPercent:actualUsedPercent:projectedExhaustion:willLastToReset:)`.
- `UsagePace.calculate(window:now:) -> UsagePace?` has no stored history or side effects.

- [ ] **Step 1: Write failing pace boundary tests**

```swift
func testPaceProjectsExhaustionBeforeReset() throws {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    let window = UsageWindow(
        id: "weekly",
        kind: .weekly,
        usedPercent: 60,
        resetAt: now.addingTimeInterval(2 * 86_400),
        durationSeconds: 7 * 86_400
    )

    let pace = try XCTUnwrap(UsagePace.calculate(window: window, now: now))

    XCTAssertEqual(pace.expectedUsedPercent, 71.428571, accuracy: 0.0001)
    XCTAssertEqual(pace.deltaPercent, -11.428571, accuracy: 0.0001)
    XCTAssertTrue(pace.willLastToReset)
    XCTAssertNil(pace.projectedExhaustion)
}

func testPaceIsHiddenBeforeThreePercentElapsed() {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    let window = UsageWindow(
        id: "five-hour",
        kind: .rolling(hours: 5),
        usedPercent: 1,
        resetAt: now.addingTimeInterval(4.9 * 3_600),
        durationSeconds: 5 * 3_600
    )

    XCTAssertNil(UsagePace.calculate(window: window, now: now))
}
```

- [ ] **Step 2: Run pace tests and confirm RED**

```bash
swift test --filter UsagePaceTests
```

Expected: compilation fails because `UsagePace` does not exist.

- [ ] **Step 3: Extract menu presentation and implement the pure pace calculation**

First move `MenuBarButtonStyle`, `MenuBarErrorState`, `MenuBarText`, and quota-progress presentation/view helpers out of `MenuBarController.swift` into `MenuBarPresentation.swift` without changing behavior; keep the existing menu tests green. Then calculate elapsed seconds as `duration - timeUntilReset`, reject invalid or out-of-window resets, require at least 3 percent elapsed, and compare clamped actual usage with `elapsed / duration * 100`. Derive linear exhaustion only when the remaining capacity divided by observed usage rate is less than time until reset.

Use these labels in `MenuBarPresentation`:

```swift
if abs(pace.deltaPercent) <= 2 {
    paceText = "On pace"
} else if pace.deltaPercent > 0 {
    paceText = "\(Int(abs(pace.deltaPercent).rounded()))% in deficit"
} else {
    paceText = "\(Int(abs(pace.deltaPercent).rounded()))% in reserve"
}
```

Render pace beneath each valid base/additional quota window. Do not show probabilities, workday assumptions, or allowance estimates.

- [ ] **Step 4: Run pace/menu tests and full unit suite**

```bash
swift test --filter UsagePaceTests
swift test --filter MenuBarTextTests
swift test
```

Expected: pace boundary tests and all existing quota semantics pass.

- [ ] **Step 5: Commit pace**

```bash
git add -- Sources/CodexWatch/Models/UsagePace.swift Sources/CodexWatch/App/MenuBarPresentation.swift Sources/CodexWatch/App/MenuBarController.swift Tests/CodexWatchTests/UsagePaceTests.swift Tests/CodexWatchTests/MenuBarTextTests.swift
git diff --cached --check
git commit -m "feat: show Codex quota pace"
```

---

### Task 5: Replace timer cancellation churn with coordinated refreshes

**Files:**
- Create: `Sources/CodexWatch/App/RefreshPolicy.swift`
- Create: `Sources/CodexWatch/App/RefreshCoordinator.swift`
- Create: `Tests/CodexWatchTests/RefreshCoordinatorTests.swift`
- Modify: `Sources/CodexWatch/App/MenuBarController.swift`
- Modify: `Sources/CodexWatch/App/MenuBarPresentation.swift`
- Modify: `Sources/CodexWatch/App/UsageAnalyticsMenuView.swift`
- Modify: `Sources/CodexWatch/App/AppDelegate.swift`
- Modify: `Tests/CodexWatchTests/MenuBarTextTests.swift`

**Interfaces:**
- Produces `RefreshFrequency`, `AdaptiveRefreshPolicy`, `RefreshTrigger`, `RefreshRequest`, `RefreshResult`, and `@MainActor RefreshCoordinator`.
- Coordinator initializer receives `now`, `sleep`, `fetch`, and `publish` closures so tests use no wall-clock delay.
- `RefreshRequest.includeAnalytics` is true for manual refreshes and for automatic generations only when the last analytics attempt is at least 15 minutes old.

- [ ] **Step 1: Write failing policy and coordination tests**

```swift
func testAdaptivePolicyUsesInteractionAndConstrainedDelays() {
    let now = Date(timeIntervalSince1970: 2_000_000_000)

    XCTAssertEqual(AdaptiveRefreshPolicy.nextDelay(
        now: now,
        lastMenuOpenAt: now.addingTimeInterval(-60),
        lowPowerMode: false,
        thermalConstrained: false
    ), 120)
    XCTAssertEqual(AdaptiveRefreshPolicy.nextDelay(
        now: now,
        lastMenuOpenAt: nil,
        lowPowerMode: true,
        thermalConstrained: false
    ), 1_800)
}

@MainActor
func testAutomaticTriggersCoalesceIntoOneFetch() async {
    let recorder = FetchRecorder()
    let coordinator = RefreshCoordinator(
        now: { Date(timeIntervalSince1970: 2_000_000_000) },
        sleep: { _ in },
        fetch: { request in await recorder.fetch(request) },
        publish: { _ in }
    )

    coordinator.trigger(.automatic)
    coordinator.trigger(.automatic)
    await recorder.releaseOneFetch()
    await coordinator.waitUntilIdleForTesting()

    XCTAssertEqual(await recorder.fetchCount, 1)
}

@MainActor
func testManualReplacementPreventsOldGenerationPublishing() async {
    let recorder = PublicationRecorder()
    let coordinator = makeControllableCoordinator(recorder: recorder)

    coordinator.trigger(.automatic)
    coordinator.trigger(.manual)
    await coordinator.completeNewestFirst()

    XCTAssertEqual(recorder.publishedIDs, ["manual"])
}

func testAutomaticAnalyticsRequestsRespectFifteenMinuteFloor() {
    let now = Date(timeIntervalSince1970: 2_000_000_000)

    XCTAssertFalse(RefreshPolicy.shouldIncludeAnalytics(
        trigger: .automatic,
        lastAttempt: now.addingTimeInterval(-899),
        now: now
    ))
    XCTAssertTrue(RefreshPolicy.shouldIncludeAnalytics(
        trigger: .automatic,
        lastAttempt: now.addingTimeInterval(-900),
        now: now
    ))
    XCTAssertTrue(RefreshPolicy.shouldIncludeAnalytics(
        trigger: .manual,
        lastAttempt: now,
        now: now
    ))
}

func testStaleQuotaCopyUsesLastSuccessfulFetchTime() {
    let now = Date(timeIntervalSince1970: 2_000_000_000)

    XCTAssertEqual(
        MenuBarText.updatedLine(
            lastUpdated: now.addingTimeInterval(-125),
            now: now
        ),
        "Updated 2m ago"
    )
}
```

Keep `FetchRecorder`, `PublicationRecorder`, and controllable continuations inside the test target. Move the existing analytics-cadence assertions out of `AnalyticsRefreshPolicy` and onto `RefreshPolicy.shouldIncludeAnalytics`.

- [ ] **Step 2: Run coordinator tests and confirm RED**

```bash
swift test --filter RefreshCoordinatorTests
```

Expected: compilation fails because refresh policy/coordinator types do not exist.

- [ ] **Step 3: Implement pure policy, generation ownership, and controller integration**

Define the preference cases exactly:

```swift
enum RefreshFrequency: Int, CaseIterable, Sendable {
    case manual = 0
    case oneMinute = 60
    case twoMinutes = 120
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case thirtyMinutes = 1_800
    case adaptive = -1
}
```

Store the preference under `codexWatch.refreshFrequency`; when it is absent, persist `.adaptive`. The Task 9 upgrade procedure pre-seeds `.oneMinute` only when it finds an installed 1.0 app with no stored choice, because 1.0 did not persist a launch marker that production code could use to distinguish upgrades from new installs. Schedule the next delay only after the current task finishes. Automatic requests share active work; manual requests increment the generation, cancel old work, and are the only new generation allowed to publish. A menu open triggers only when the quota snapshot is older than 60 seconds. `stop()` cancels timer/task and prevents future publication.

Replace the old `AnalyticsRefreshPolicy` in `UsageAnalyticsMenuView.swift`. Preserve a last successful quota snapshot on quota errors, render the status button with secondary/dim emphasis, and add deterministic `Updated <relative time>` copy using an injected/reference date. Preserve the last analytics dataset when only analytics fails and publish an analytics-stale flag for the dashboard model in Task 7. Never log the associated response or error payload.

Make `MenuBarController` an `NSMenuDelegate`, record menu-open time in memory, and delegate refresh mechanics to the coordinator. Keep weak captures for AppKit owners.

- [ ] **Step 4: Run coordinator, menu, and complete tests**

```bash
swift test --filter RefreshCoordinatorTests
swift test --filter MenuBarTextTests
swift test
```

Expected: coordination tests pass without real sleeps, and the complete suite reports zero failures.

- [ ] **Step 5: Commit refresh reliability**

```bash
git add -- Sources/CodexWatch/App/RefreshPolicy.swift Sources/CodexWatch/App/RefreshCoordinator.swift Sources/CodexWatch/App/MenuBarController.swift Sources/CodexWatch/App/MenuBarPresentation.swift Sources/CodexWatch/App/UsageAnalyticsMenuView.swift Sources/CodexWatch/App/AppDelegate.swift Tests/CodexWatchTests/RefreshCoordinatorTests.swift Tests/CodexWatchTests/MenuBarTextTests.swift
git diff --cached --check
git commit -m "refactor: coordinate Codex refreshes"
```

---

### Task 6: Add deterministic CSV export

**Files:**
- Create: `Sources/CodexWatch/Export/UsageAnalyticsCSVExporter.swift`
- Create: `Tests/CodexWatchTests/UsageAnalyticsCSVExporterTests.swift`

**Interfaces:**
- Produces `UsageAnalyticsCSVExporter.string(projection:) throws -> String` and `UsageAnalyticsCSVExporter.suggestedFilename(range:dataThrough:) -> String`.
- Consumes only `UsageAnalyticsProjection`; it has no UI or filesystem dependency.

- [ ] **Step 1: Write failing RFC 4180 export tests**

```swift
func testCSVContainsMetadataDailyModelsAndClients() throws {
    let projection = makeCSVProjection()

    let csv = try UsageAnalyticsCSVExporter.string(projection: projection)

    XCTAssertEqual(csv, """
    Codex Watch analytics,30d\r
    Data through,2026-08-19\r
    Coverage,29/30 days\r
    \r
    Daily usage\r
    Date,Status,Total tokens,Input tokens,Cached input,Output tokens,Turns,Chats\r
    2026-08-19,Observed,100,20,30,50,4,2\r
    2026-08-20,Missing,,,,,,\r
    \r
    Model activity\r
    Model,Turns,Chats,Credits,Turn share\r
    "gpt-5.6-sol, preview",4,2,1.5,100%\r
    \r
    Client tokens\r
    Client,Total tokens,Input tokens,Cached input,Output tokens,Turns,Chats\r
    CODEX_DESKTOP_APP,100,20,30,50,4,2\r

    """)
}

func testCSVQuotesQuotesCommasAndNewlines() {
    XCTAssertEqual(UsageAnalyticsCSVExporter.escape("a,\"b\"\nc"), "\"a,\"\"b\"\"\nc\"")
}
```

- [ ] **Step 2: Run exporter tests and confirm RED**

```bash
swift test --filter UsageAnalyticsCSVExporterTests
```

Expected: compilation fails because the exporter does not exist.

- [ ] **Step 3: Implement pure CSV serialization**

Serialize CRLF line endings, quote any value containing comma, quote, CR, or LF, and double embedded quotes. Use POSIX date/decimal formatting. Include selected-range metadata, every daily cell including missing dates, model activity, and client tokens. Never include account identifiers, export paths, tokens used for authentication, or hidden raw fields.

- [ ] **Step 4: Run exporter and projection tests**

```bash
swift test --filter UsageAnalyticsCSVExporterTests
swift test --filter UsageAnalyticsProjectionTests
```

Expected: literal CSV and projection tests pass.

- [ ] **Step 5: Commit export support**

```bash
git add -- Sources/CodexWatch/Export/UsageAnalyticsCSVExporter.swift Tests/CodexWatchTests/UsageAnalyticsCSVExporterTests.swift
git diff --cached --check
git commit -m "feat: export Codex analytics CSV"
```

---

### Task 7: Build the reusable native analytics dashboard

**Files:**
- Create: `Sources/CodexWatch/App/AnalyticsDashboardModel.swift`
- Create: `Sources/CodexWatch/App/AnalyticsDashboardView.swift`
- Create: `Sources/CodexWatch/App/AnalyticsWindowController.swift`
- Create: `Tests/CodexWatchTests/AnalyticsDashboardModelTests.swift`
- Modify: `Sources/CodexWatch/App/MenuBarController.swift`
- Modify: `Sources/CodexWatch/App/MenuBarPresentation.swift`
- Modify: `Sources/CodexWatch/App/UsageAnalyticsMenuView.swift`
- Modify: `Tests/CodexWatchTests/MenuBarTextTests.swift`

**Interfaces:**
- `@MainActor AnalyticsDashboardModel: ObservableObject` publishes dataset, range, projection, stale/error status, and `csvString()`.
- `@MainActor AnalyticsWindowController.show(dataset:errorState:)` reuses one `NSWindow` and owns `NSSavePanel` export.
- `AnalyticsDashboardView` reads the model only; it performs no network or filesystem work.

- [ ] **Step 1: Write failing dashboard state tests**

```swift
@MainActor
func testDashboardRestoresRangeAndReprojectsNewDataset() throws {
    let defaults = UserDefaults(suiteName: #function)!
    defaults.removePersistentDomain(forName: #function)
    defaults.set(90, forKey: "codexWatch.analyticsRange")
    let model = AnalyticsDashboardModel(defaults: defaults, calendar: utcCalendar())

    model.update(dataset: makeDashboardDataset(total: 100), error: nil, now: day("2026-08-20"))

    XCTAssertEqual(model.range, .days90)
    XCTAssertEqual(model.projection?.totalTokens, 100)

    model.range = .days7
    XCTAssertEqual(defaults.integer(forKey: "codexWatch.analyticsRange"), 7)
}

@MainActor
func testDashboardKeepsLastDatasetAndMarksAnalyticsStale() {
    let model = AnalyticsDashboardModel(defaults: UserDefaults(suiteName: #function)!)
    model.update(dataset: makeDashboardDataset(total: 100), error: nil, now: .now)
    model.update(dataset: nil, error: .analyticsUnavailable, now: .now)

    XCTAssertEqual(model.projection?.totalTokens, 100)
    XCTAssertTrue(model.isStale)
}
```

Add a menu presentation test asserting additional windows appear with their own titles while the top weekly value remains unchanged.

- [ ] **Step 2: Run dashboard/menu tests and confirm RED**

```bash
swift test --filter AnalyticsDashboardModelTests
swift test --filter MenuBarTextTests/testAdditionalQuotaRowsDoNotChangeTopWeeklyValue
```

Expected: compilation fails because the dashboard model and named quota presentation do not exist.

- [ ] **Step 3: Implement state, window, charts, and export wiring**

Use a 940×720 resizable `NSWindow` with title `Codex Watch Analytics`, automatic frame saving name `CodexWatchAnalyticsWindow`, and one `NSHostingController`. Build the SwiftUI hierarchy with:

```swift
VStack(spacing: 16) {
    header
    Picker("Range", selection: $model.range) {
        ForEach(AnalyticsRange.allCases) { range in Text(range.title).tag(range) }
    }
    .pickerStyle(.segmented)
    summaryCards
    tokenChart
    activityHeatmap
    modelActivityTable
    clientTokenTable
    footer
}
```

Use Apple Charts for the selected-range token chart. Implement the heatmap with `LazyVGrid` so missing dates use a stroked neutral cell and observed zero dates use a filled zero-intensity cell. Give every cell a date/status accessibility label. Present model columns as activity, not tokens. Wire `Export CSV…` through `NSSavePanel`, then atomically write UTF-8 data to the selected URL; display an `NSAlert` on failure without logging the path.

Extend the extracted menu presentation with `Open Analytics Dashboard…`; keep `Open Usage Analytics…` as the official-web action. When new snapshots arrive, update both the menu and any open dashboard.

- [ ] **Step 4: Run model/menu tests and full suite**

```bash
swift test --filter AnalyticsDashboardModelTests
swift test --filter MenuBarTextTests
swift test
```

Expected: all dashboard-state, menu, projection, export, and legacy tests pass.

- [ ] **Step 5: Commit the dashboard**

```bash
git add -- Sources/CodexWatch/App/AnalyticsDashboardModel.swift Sources/CodexWatch/App/AnalyticsDashboardView.swift Sources/CodexWatch/App/AnalyticsWindowController.swift Sources/CodexWatch/App/MenuBarController.swift Sources/CodexWatch/App/MenuBarPresentation.swift Sources/CodexWatch/App/UsageAnalyticsMenuView.swift Tests/CodexWatchTests/AnalyticsDashboardModelTests.swift Tests/CodexWatchTests/MenuBarTextTests.swift
git diff --cached --check
git commit -m "feat: add native Codex analytics dashboard"
```

---

### Task 8: Supersede contracts, document behavior, and bump version

**Files:**
- Modify: `AGENTS.md`
- Modify: `README.md`
- Modify: `Resources/Info.plist`
- Modify: `docs/contracts/behavior-contracts.yaml`
- Modify: `docs/decisions/007-usage-analytics.md`
- Modify: `docs/decisions/README.md`
- Create: `docs/decisions/008-api-dashboard-and-refresh.md`
- Modify: `docs/specs/codex-watch-1.0.md` only to mark it historical and point to the 1.1 design; do not rewrite its recorded 1.0 behavior.

**Interfaces:**
- Produces active contracts `DASHBOARD-SURFACE-011`, `USAGE-ANALYTICS-012`, and `REFRESH-COORDINATION-013`.
- Sets `CFBundleShortVersionString=1.1.0` and `CFBundleVersion=16`.

- [ ] **Step 1: Update the harness and decision records**

Mark `MENU-BAR-001` superseded by `DASHBOARD-SURFACE-011` and `USAGE-ANALYTICS-010` superseded by `USAGE-ANALYTICS-012`. Keep `QUOTA-SEMANTICS-002` active. Add exact positive/negative examples and guards for dashboard visibility, 365-day analytics coverage, model/client semantics, and coordinated refreshes. Amend `PRIVACY-BOUNDARY-003` to permit only the wider same-host response and user-requested CSV.

Record in ADR 008:

- The menu bar remains persistent while one user-opened analytics window is allowed.
- One 365-day response is projected into smaller ranges.
- Model rows represent activity, client rows represent tokens.
- Missing dates are gaps and comparisons require 90 percent coverage.
- Plain adaptive refresh never scans processes or sessions.
- Local history and WebView extras remain separate decisions.

- [ ] **Step 2: Update product documentation and version**

Document every returned quota window, dashboard range, coverage/as-of labels, pace limitations, CSV behavior, refresh options, in-memory data retention, and the unchanged no-updater/no-session-scan boundary. Change the plist values with:

```bash
plutil -replace CFBundleShortVersionString -string 1.1.0 Resources/Info.plist
plutil -replace CFBundleVersion -string 16 Resources/Info.plist
```

- [ ] **Step 3: Validate contracts and metadata**

```bash
./scripts/check_contracts.sh
plutil -lint Resources/Info.plist
test "$(plutil -extract CFBundleShortVersionString raw -o - Resources/Info.plist)" = "1.1.0"
test "$(plutil -extract CFBundleVersion raw -o - Resources/Info.plist)" = "16"
if rg -n 'TBD|TODO|implement later|fill in details' AGENTS.md README.md docs/contracts docs/decisions Resources/Info.plist; then
  exit 1
fi
```

Expected: contract and plist checks succeed and the placeholder scan prints nothing.

- [ ] **Step 4: Run the complete unit suite after contract changes**

```bash
swift test
```

Expected: zero failures.

- [ ] **Step 5: Commit contracts, docs, and version**

```bash
git add -- AGENTS.md README.md Resources/Info.plist docs/contracts/behavior-contracts.yaml docs/decisions/007-usage-analytics.md docs/decisions/008-api-dashboard-and-refresh.md docs/decisions/README.md docs/specs/codex-watch-1.0.md
git diff --cached --check
git commit -m "docs: define Codex Watch 1.1 contracts"
```

---

### Task 9: Review, verify, install, relaunch, and publish to main

**Files:**
- Inspect all paths changed since plan base commit `04c636e6f638b230c479fa5e72123df85b3d1617`.
- Do not create a branch, pull request, or version tag in this task.

**Interfaces:**
- Produces a verified local `Codex Watch.app`, release ZIP/checksum, installed replacement, running 1.1.0 process, and synchronized `origin/main`.

- [ ] **Step 1: Request a read-only code review of the complete feature**

Use the requesting-code-review template with:

```text
DESCRIPTION: Codex Watch 1.1 API dashboard, quota capabilities, 365-day analytics projections, pace, refresh coordination, CSV export, native window, and contract/version updates.
PLAN_OR_REQUIREMENTS: docs/superpowers/specs/2026-08-20-api-dashboard-design.md and docs/superpowers/plans/2026-08-20-api-dashboard.md
BASE_SHA: 04c636e6f638b230c479fa5e72123df85b3d1617
HEAD_SHA: the current verified HEAD
```

Fix every Critical and Important finding through a new failing regression test, focused green run, and separate commit. Record Minor findings in the handoff only when they do not undermine the spec.

- [ ] **Step 2: Run fresh full verification**

```bash
./scripts/check_contracts.sh
swift test
VERIFY_DIR=$(mktemp -d /private/tmp/codex-watch-verify.XXXXXX)
./scripts/verify.sh "$VERIFY_DIR"
RELEASE_DIR="/private/tmp/codex-watch-release-1.1.0-$(git rev-parse --short HEAD)"
test ! -e "$RELEASE_DIR"
mkdir "$RELEASE_DIR"
ARCHITECTURES="arm64 x86_64" ARCHIVE_ARCH=universal ./scripts/release.sh "$RELEASE_DIR"
```

Expected: all commands exit zero; the app verifies as version 1.1.0 build 16 and the release directory contains the universal ZIP and matching SHA-256 file.

- [ ] **Step 3: Perform recoverable installation and relaunch**

Resolve explicit paths and preserve the previous app:

```bash
RELEASE_DIR="/private/tmp/codex-watch-release-1.1.0-$(git rev-parse --short HEAD)"
INSTALL_SOURCE="$RELEASE_DIR/Codex Watch.app"
INSTALLED_APP="/Applications/Codex Watch.app"
BACKUP_APP="/Applications/Codex Watch 1.0.0 Backup.app"
test -d "$INSTALL_SOURCE"
if test -d "$INSTALLED_APP"; then
  test ! -e "$BACKUP_APP"
  INSTALLED_VERSION=$(plutil -extract CFBundleShortVersionString raw -o - "$INSTALLED_APP/Contents/Info.plist")
  if test "$INSTALLED_VERSION" = "1.0.0" \
      && ! defaults read com.moebis.codexwatch codexWatch.refreshFrequency >/dev/null 2>&1; then
    defaults write com.moebis.codexwatch codexWatch.refreshFrequency -int 60
  fi
fi
osascript -e 'tell application "Codex Watch" to quit' 2>/dev/null || true
if test -d "$INSTALLED_APP"; then
  mv "$INSTALLED_APP" "$BACKUP_APP"
fi
ditto "$INSTALL_SOURCE" "$INSTALLED_APP"
open -a "$INSTALLED_APP"
```

If the explicit backup path already exists, stop and select a new versioned backup path rather than overwriting it. The preference write is a one-time, no-overwrite migration for this detected 1.0 installation; fresh preference domains remain Adaptive.

- [ ] **Step 4: Verify the installed bundle and live process**

```bash
./scripts/verify_app.sh "/Applications/Codex Watch.app"
test "$(plutil -extract CFBundleShortVersionString raw -o - '/Applications/Codex Watch.app/Contents/Info.plist')" = "1.1.0"
test "$(plutil -extract CFBundleVersion raw -o - '/Applications/Codex Watch.app/Contents/Info.plist')" = "16"
pgrep -fl '/Applications/Codex Watch.app/Contents/MacOS/CodexWatch'
```

Manually inspect the menu-bar weekly percentage, extra Spark windows, pace labels, reset-credit inventory, stale/freshness copy, dashboard range switching, chart/heatmap gaps, model/client headings, CSV export, window reopening, and quit/relaunch behavior.

- [ ] **Step 5: Confirm scope, push main, and verify synchronization**

```bash
git status --short --branch
git diff --check 04c636e6f638b230c479fa5e72123df85b3d1617..HEAD
git log --oneline 04c636e6f638b230c479fa5e72123df85b3d1617..HEAD
git push origin main
test "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)"
git status --short --branch
```

Expected: only intentional commits are present, push succeeds, local `main` equals `origin/main`, and the worktree is clean. Do not create a tag because the user authorized main publication but did not request a GitHub Release for 1.1.0.

---

## Plan self-review checklist

- Every 1.1 spec requirement maps to Tasks 1–9.
- The local history index, browser extras, status polling, notifications, widgets, CLI, multi-account support, and multi-provider abstractions remain outside this plan.
- Production interfaces have one consistent name across producer and consumer tasks.
- Every new production behavior begins with a focused failing test and explicit RED command.
- No task uses a branch, pull request, automatic updater, session scan, new host, or third-party dependency.
- Installation is recoverable and refuses to overwrite an existing backup path.
- Final publication is direct to `main` and does not create a release tag.
