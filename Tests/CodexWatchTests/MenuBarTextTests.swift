import AppKit
import Foundation
import XCTest
@testable import CodexWatch

@MainActor
final class MenuBarTextTests: XCTestCase {
    func testMenuDoesNotOfferRepositoryUpdateChecks() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let controller = MenuBarController(
            statusItem: statusItem,
            authReader: CodexAuthReader(
                environment: [:],
                homeDirectory: URL(fileURLWithPath: "/definitely/not/the-test-home")
            ),
            session: URLSession(configuration: .ephemeral)
        )
        controller.start()
        defer { controller.stop() }

        let menuTitles = statusItem.menu?.items.map(\.title) ?? []

        XCTAssertFalse(menuTitles.contains { $0.localizedCaseInsensitiveContains("update") })
    }

    func testMenuOffersOfficialUsageAnalyticsWithoutRestoringUpdates() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let controller = MenuBarController(
            statusItem: statusItem,
            authReader: CodexAuthReader(
                environment: [:],
                homeDirectory: URL(fileURLWithPath: "/definitely/not/the-test-home")
            ),
            session: URLSession(configuration: .ephemeral)
        )
        controller.start()
        defer { controller.stop() }

        let menuTitles = statusItem.menu?.items.map(\.title) ?? []

        XCTAssertTrue(menuTitles.contains("Open Usage Analytics…"))
        XCTAssertTrue(menuTitles.contains("Refresh Frequency"))
        XCTAssertFalse(menuTitles.contains { $0.localizedCaseInsensitiveContains("update") })
        XCTAssertEqual(
            AppIdentity.usageAnalyticsURL.absoluteString,
            "https://chatgpt.com/codex/cloud/settings/analytics#usage"
        )
    }

    func testRefreshPolicyLimitsAutomaticAnalyticsButAllowsManualRefresh() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)

        XCTAssertTrue(RefreshPolicy.shouldIncludeAnalytics(trigger: .automatic, lastAttempt: nil, now: now))
        XCTAssertFalse(
            RefreshPolicy.shouldIncludeAnalytics(
                trigger: .automatic,
                lastAttempt: now.addingTimeInterval(-899),
                now: now
            )
        )
        XCTAssertTrue(
            RefreshPolicy.shouldIncludeAnalytics(
                trigger: .automatic,
                lastAttempt: now.addingTimeInterval(-900),
                now: now
            )
        )
        XCTAssertTrue(
            RefreshPolicy.shouldIncludeAnalytics(
                trigger: .manual,
                lastAttempt: now,
                now: now
            )
        )
    }

    func testUsageAnalyticsPresentationFormatsSixTruthfulThirtyDayMetrics() {
        let projection = makeAnalyticsProjection(
            totalTokens: 30_300_000_000,
            inputTokens: 1_200_000,
            cachedInputTokens: 999,
            outputTokens: 2_345,
            turns: 3_427,
            chats: 42
        )

        let presentation = UsageAnalyticsPresentation(projection: projection)

        XCTAssertEqual(presentation.title, "Last 30 days")
        XCTAssertEqual(presentation.totalTokens, "30.3B")
        XCTAssertEqual(presentation.inputTokens, "1.2M")
        XCTAssertEqual(presentation.cachedInputTokens, "999")
        XCTAssertEqual(presentation.outputTokens, "2.3K")
        XCTAssertEqual(presentation.turns, "3.4K")
        XCTAssertEqual(presentation.chats, "42")
        XCTAssertEqual(presentation.coverage, "1/30 days")
        XCTAssertFalse(presentation.dataThrough.isEmpty)
    }

    func testUsageAnalyticsMenuContainsSixLabeledRows() {
        let view = UsageAnalyticsMenuView(
            presentation: UsageAnalyticsPresentation(
                projection: makeAnalyticsProjection(
                    totalTokens: 14_000,
                    inputTokens: 2_500,
                    cachedInputTokens: 4_500,
                    outputTokens: 7_000,
                    turns: 22,
                    chats: 5
                )
            )
        )
        let values = textValues(in: view)

        XCTAssertTrue(values.contains("Last 30 days"))
        XCTAssertTrue(values.contains("Total tokens"))
        XCTAssertTrue(values.contains("Input tokens"))
        XCTAssertTrue(values.contains("Cached input"))
        XCTAssertTrue(values.contains("Output tokens"))
        XCTAssertTrue(values.contains("Turns"))
        XCTAssertTrue(values.contains("Chats"))
        XCTAssertTrue(values.contains("Coverage"))
        XCTAssertTrue(values.contains("Data through"))
        XCTAssertEqual(view.frame.width, UsageAnalyticsMenuView.width)
    }

    func testStatusButtonUsesCompactNativeImageAndTitleLayout() {
        let button = NSButton(frame: .zero)

        MenuBarButtonStyle.apply(to: button)

        XCTAssertTrue(button.imageHugsTitle)
        XCTAssertEqual(button.imagePosition, .imageLeading)
        XCTAssertEqual(button.alignment, .center)
        XCTAssertEqual(button.font?.pointSize, MenuBarButtonStyle.fontSize)
    }

    func testStatusTitleShowsRoundedWeeklyRemainingPercent() {
        let snapshot = UsageSnapshot(
            windows: [UsageWindow(id: "weekly", kind: .weekly, usedPercent: 31.6)]
        )

        XCTAssertEqual(MenuBarText.statusTitle(snapshot: snapshot), "68%")
        XCTAssertEqual(MenuBarText.summary(snapshot: snapshot, error: nil), "Weekly remaining: 68%")
    }

    func testUnavailableStatesNeverExposeErrorDetails() {
        XCTAssertEqual(MenuBarText.statusTitle(snapshot: nil), "—")
        XCTAssertEqual(
            MenuBarText.summary(snapshot: nil, error: .signInRequired),
            "Sign in to Codex again"
        )
        XCTAssertEqual(
            MenuBarText.summary(snapshot: nil, error: .quotaUnavailable),
            "Quota unavailable"
        )
    }

    func testStalePresentationShowsErrorAndLastSuccessfulUpdateTime() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let snapshot = UsageSnapshot(
            windows: [UsageWindow(id: "weekly", kind: .weekly, usedPercent: 25)],
            fetchedAt: now.addingTimeInterval(-125)
        )

        let presentation = QuotaProgressPresentation(
            snapshot: snapshot,
            error: .quotaUnavailable,
            now: now
        )
        let values = textValues(in: QuotaProgressMenuView(presentation: presentation))

        XCTAssertEqual(presentation.statusDetail, "Quota unavailable")
        XCTAssertEqual(presentation.updatedValue, "Updated 2m ago")
        XCTAssertTrue(values.contains("Quota unavailable"))
        XCTAssertTrue(values.contains("Updated 2m ago"))
    }

    func testResetLineUsesStableEnglishFormatting() {
        let snapshot = UsageSnapshot(
            windows: [
                UsageWindow(
                    id: "weekly",
                    kind: .weekly,
                    usedPercent: 10,
                    resetAt: Date(timeIntervalSince1970: 1_768_415_045)
                )
            ]
        )

        XCTAssertTrue(MenuBarText.resetLine(snapshot: snapshot)?.hasPrefix("Resets: ") == true)
    }

    func testProgressPresentationUsesRemainingQuotaAndExactWindowDuration() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let snapshot = UsageSnapshot(
            plan: .pro,
            creditsRemaining: .balance("12.50"),
            windows: [
                UsageWindow(
                    id: "weekly",
                    kind: .weekly,
                    usedPercent: 19,
                    resetAt: now.addingTimeInterval(2 * 24 * 60 * 60),
                    durationSeconds: 7 * 24 * 60 * 60
                )
            ]
        )

        let presentation = QuotaProgressPresentation(snapshot: snapshot, error: nil, now: now)

        XCTAssertEqual(presentation.planValue, "Pro")
        XCTAssertEqual(presentation.creditsRemainingValue, "12.50")
        XCTAssertEqual(presentation.quotaValue, "81%")
        XCTAssertEqual(try XCTUnwrap(presentation.quotaProgress), 0.81, accuracy: 0.0001)
        XCTAssertEqual(presentation.resetValue, "2d 0h")
        XCTAssertEqual(try XCTUnwrap(presentation.resetProgress), 2.0 / 7.0, accuracy: 0.0001)
        XCTAssertNotNil(presentation.resetDetail)
    }

    func testProgressPresentationIncludesEveryQuotaWindowAndItsPace() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let weekly = UsageWindow(
            id: "weekly",
            kind: .weekly,
            usedPercent: 60,
            resetAt: now.addingTimeInterval(2 * 86_400),
            durationSeconds: 7 * 86_400
        )
        let fiveHour = UsageWindow(
            id: "primary",
            kind: .rolling(hours: 5),
            usedPercent: 60,
            resetAt: now.addingTimeInterval(2.5 * 3_600),
            durationSeconds: 5 * 3_600
        )
        let spark = UsageWindow(
            id: "codex-spark",
            kind: .rolling(hours: 5),
            usedPercent: 25,
            resetAt: now.addingTimeInterval(2.5 * 3_600),
            durationSeconds: 5 * 3_600
        )
        let codeReview = UsageWindow(
            id: "code-review-primary",
            kind: .daily,
            usedPercent: 50,
            resetAt: now.addingTimeInterval(12 * 3_600),
            durationSeconds: 24 * 3_600
        )
        let snapshot = UsageSnapshot(
            windows: [fiveHour, weekly],
            additionalWindows: [NamedUsageWindow(id: spark.id, title: "Codex Spark 5-hour", window: spark)],
            codeReviewWindows: [NamedUsageWindow(id: codeReview.id, title: "Code Review", window: codeReview)]
        )

        let presentation = QuotaProgressPresentation(snapshot: snapshot, error: nil, now: now)

        XCTAssertEqual(
            presentation.quotaWindows.map(\.title),
            ["Weekly", "5-hour", "Codex Spark 5-hour", "Code Review"]
        )
        XCTAssertEqual(presentation.quotaWindows[0].paceText, "11% in reserve")
        XCTAssertEqual(presentation.quotaWindows[1].paceText, "10% in deficit")
        XCTAssertEqual(presentation.quotaWindows[2].paceText, "25% in reserve")
        XCTAssertEqual(presentation.quotaWindows[3].paceText, "On pace")
    }

    func testProgressMenuRendersNamedQuotaAndPaceLabels() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let spark = UsageWindow(
            id: "codex-spark",
            kind: .rolling(hours: 5),
            usedPercent: 25,
            resetAt: now.addingTimeInterval(2.5 * 3_600),
            durationSeconds: 5 * 3_600
        )
        let view = QuotaProgressMenuView(
            presentation: QuotaProgressPresentation(
                snapshot: UsageSnapshot(
                    windows: [],
                    additionalWindows: [NamedUsageWindow(
                        id: spark.id,
                        title: "Codex Spark 5-hour",
                        window: spark
                    )]
                ),
                error: nil,
                now: now
            )
        )

        let values = textValues(in: view)
        XCTAssertTrue(values.contains("Codex Spark 5-hour remaining"))
        XCTAssertTrue(values.contains("25% in reserve"))
    }

    func testPlanDisplayUsesNormalizedNameAndNeverExposesUnknownValues() {
        let known = QuotaProgressPresentation(
            snapshot: UsageSnapshot(plan: .proLite, windows: []),
            error: nil,
            now: .now
        )
        let missing = QuotaProgressPresentation(
            snapshot: UsageSnapshot(windows: []),
            error: nil,
            now: .now
        )

        XCTAssertEqual(known.planValue, "Pro Lite")
        XCTAssertEqual(missing.planValue, "Unavailable")
    }

    func testResetProgressIsClampedAndUnavailableDataIsNotFabricated() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let expired = UsageSnapshot(
            windows: [
                UsageWindow(
                    id: "weekly",
                    kind: .weekly,
                    usedPercent: 50,
                    resetAt: now.addingTimeInterval(-60),
                    durationSeconds: 604_800
                )
            ]
        )
        let missingDuration = UsageSnapshot(
            windows: [
                UsageWindow(
                    id: "weekly",
                    kind: .weekly,
                    usedPercent: 50,
                    resetAt: now.addingTimeInterval(60)
                )
            ]
        )

        XCTAssertEqual(
            QuotaProgressPresentation(snapshot: expired, error: nil, now: now).resetProgress,
            0
        )
        let unavailable = QuotaProgressPresentation(snapshot: missingDuration, error: nil, now: now)
        XCTAssertNil(unavailable.resetProgress)
        XCTAssertEqual(unavailable.resetValue, "Unavailable")
    }

    func testProgressMenuViewContainsTwoNativeProgressIndicators() {
        let presentation = QuotaProgressPresentation(snapshot: nil, error: nil, now: .now)
        let view = QuotaProgressMenuView(presentation: presentation)
        let progressBars = progressIndicators(in: view)

        XCTAssertEqual(progressBars.count, 2)
        XCTAssertTrue(progressBars.allSatisfy { $0 is NeutralProgressIndicator })
        XCTAssertEqual(NeutralProgressIndicator.fillColor, .secondaryLabelColor)
        XCTAssertEqual(NeutralProgressIndicator.trackColor, .separatorColor)
        XCTAssertEqual(view.frame.size.width, QuotaProgressMenuView.width)
        XCTAssertEqual(view.frame.size.height, QuotaProgressMenuView.height)
        XCTAssertTrue(textValues(in: view).contains("Plan"))
        XCTAssertTrue(textValues(in: view).contains("Unavailable"))
    }

    func testProgressMenuShowsCreditsRemainingOnlyWhenAvailable() {
        let visible = QuotaProgressMenuView(
            presentation: QuotaProgressPresentation(
                snapshot: UsageSnapshot(creditsRemaining: .balance("-1.25"), windows: []),
                error: nil,
                now: .now
            )
        )
        let hidden = QuotaProgressMenuView(
            presentation: QuotaProgressPresentation(
                snapshot: UsageSnapshot(windows: []),
                error: nil,
                now: .now
            )
        )

        XCTAssertTrue(textValues(in: visible).contains("Credits remaining"))
        XCTAssertTrue(textValues(in: visible).contains("-1.25"))
        XCTAssertFalse(textValues(in: hidden).contains("Credits remaining"))
        XCTAssertEqual(
            visible.frame.height,
            QuotaProgressMenuView.height + QuotaProgressMenuView.creditsRemainingHeightIncrement
        )
    }

    func testProgressPresentationShowsUnlimitedCredits() {
        let presentation = QuotaProgressPresentation(
            snapshot: UsageSnapshot(creditsRemaining: .unlimited, windows: []),
            error: nil,
            now: .now
        )

        XCTAssertEqual(presentation.creditsRemainingValue, "Unlimited")
    }

    func testResetCreditsShowAvailableCountIncludingZeroAndHideWhenMissing() {
        let twoCredits = UsageSnapshot(windows: [], availableResetCredits: 2)
        let zeroCredits = UsageSnapshot(windows: [], availableResetCredits: 0)
        let missingCredits = UsageSnapshot(windows: [])

        XCTAssertEqual(
            QuotaProgressPresentation(snapshot: twoCredits, error: nil, now: .now).resetCreditsValue,
            "2 available"
        )
        XCTAssertEqual(
            QuotaProgressPresentation(snapshot: zeroCredits, error: nil, now: .now).resetCreditsValue,
            "0 available"
        )
        XCTAssertNil(
            QuotaProgressPresentation(snapshot: missingCredits, error: nil, now: .now).resetCreditsValue
        )
    }

    func testResetCreditExpiryUsesLocalDateAndKeepsWeeklyResetSeparate() {
        let expiry = Date(timeIntervalSince1970: 1_893_561_045)
        let oneCredit = UsageSnapshot(
            windows: [],
            availableResetCredits: 1,
            nextResetCreditExpiry: expiry
        )
        let multipleCredits = UsageSnapshot(
            windows: [],
            availableResetCredits: 2,
            nextResetCreditExpiry: expiry
        )

        XCTAssertTrue(
            QuotaProgressPresentation(snapshot: oneCredit, error: nil, now: .now)
                .resetCreditsDetail?
                .hasPrefix("Expires: ") == true
        )
        XCTAssertTrue(
            QuotaProgressPresentation(snapshot: multipleCredits, error: nil, now: .now)
                .resetCreditsDetail?
                .hasPrefix("Next expires: ") == true
        )
        XCTAssertNil(MenuBarText.resetLine(snapshot: oneCredit))
    }

    func testResetCreditExpiryIsHiddenWithoutAPositiveCount() {
        let expiry = Date(timeIntervalSince1970: 1_893_561_045)

        XCTAssertNil(
            QuotaProgressPresentation(
                snapshot: UsageSnapshot(windows: [], nextResetCreditExpiry: expiry),
                error: nil,
                now: .now
            ).resetCreditsDetail
        )
        XCTAssertNil(
            QuotaProgressPresentation(
                snapshot: UsageSnapshot(
                    windows: [],
                    availableResetCredits: 0,
                    nextResetCreditExpiry: expiry
                ),
                error: nil,
                now: .now
            ).resetCreditsDetail
        )
    }

    func testResetCreditProgressUsesExactGrantToExpiryDuration() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let snapshot = UsageSnapshot(
            windows: [],
            availableResetCredits: 1,
            nextResetCreditGrantedAt: now.addingTimeInterval(-10 * 24 * 60 * 60),
            nextResetCreditExpiry: now.addingTimeInterval(20 * 24 * 60 * 60)
        )

        let presentation = QuotaProgressPresentation(snapshot: snapshot, error: nil, now: now)

        XCTAssertEqual(try XCTUnwrap(presentation.resetCreditsProgress), 2.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(
            QuotaProgressPresentation(
                snapshot: snapshot,
                error: nil,
                now: now.addingTimeInterval(21 * 24 * 60 * 60)
            ).resetCreditsProgress,
            0
        )
    }

    func testResetCreditProgressDoesNotAssumeMissingOrInvalidDuration() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let missingGrant = UsageSnapshot(
            windows: [],
            availableResetCredits: 1,
            nextResetCreditExpiry: now.addingTimeInterval(60)
        )
        let invalidDuration = UsageSnapshot(
            windows: [],
            availableResetCredits: 1,
            nextResetCreditGrantedAt: now.addingTimeInterval(120),
            nextResetCreditExpiry: now.addingTimeInterval(60)
        )

        XCTAssertNil(
            QuotaProgressPresentation(snapshot: missingGrant, error: nil, now: now).resetCreditsProgress
        )
        XCTAssertNil(
            QuotaProgressPresentation(snapshot: invalidDuration, error: nil, now: now).resetCreditsProgress
        )
    }

    func testProgressMenuShowsResetCreditsRowOnlyWhenAvailable() {
        let visiblePresentation = QuotaProgressPresentation(
            snapshot: UsageSnapshot(windows: [], availableResetCredits: 2),
            error: nil,
            now: .now
        )
        let hiddenPresentation = QuotaProgressPresentation(
            snapshot: UsageSnapshot(windows: []),
            error: nil,
            now: .now
        )

        let visibleView = QuotaProgressMenuView(presentation: visiblePresentation)
        let hiddenView = QuotaProgressMenuView(presentation: hiddenPresentation)

        XCTAssertTrue(textValues(in: visibleView).contains("Reset credits"))
        XCTAssertTrue(textValues(in: visibleView).contains("2 available"))
        XCTAssertFalse(textValues(in: hiddenView).contains("Reset credits"))
        XCTAssertEqual(visibleView.frame.height, QuotaProgressMenuView.heightWithResetCredits)
    }

    func testProgressMenuShowsResetCreditExpiryWhenAvailable() {
        let presentation = QuotaProgressPresentation(
            snapshot: UsageSnapshot(
                windows: [],
                availableResetCredits: 1,
                nextResetCreditGrantedAt: Date(timeIntervalSince1970: 1_890_969_045),
                nextResetCreditExpiry: Date(timeIntervalSince1970: 1_893_561_045)
            ),
            error: nil,
            now: .now
        )

        let view = QuotaProgressMenuView(presentation: presentation)
        let progressBars = progressIndicators(in: view)

        XCTAssertTrue(textValues(in: view).contains { $0.hasPrefix("Expires: ") })
        XCTAssertEqual(progressBars.count, 3)
        XCTAssertEqual(
            progressBars.last?.toolTip,
            "Time remaining until next reset credit expires"
        )
        XCTAssertEqual(view.frame.height, QuotaProgressMenuView.heightWithResetCreditProgress)
    }

    private func progressIndicators(in view: NSView) -> [NSProgressIndicator] {
        view.subviews.flatMap { child in
            (child as? NSProgressIndicator).map { [$0] } ?? progressIndicators(in: child)
        }
    }

    private func makeAnalyticsProjection(
        totalTokens: Int64,
        inputTokens: Int64,
        cachedInputTokens: Int64,
        outputTokens: Int64,
        turns: Int64,
        chats: Int64
    ) -> UsageAnalyticsProjection {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let end = calendar.date(from: DateComponents(year: 2026, month: 8, day: 20))!
        let start = calendar.date(byAdding: .day, value: -364, to: end)!
        let day = UsageAnalyticsDay(
            date: end,
            totals: UsageTokenTotals(
                totalTokens: totalTokens,
                uncachedInputTokens: inputTokens,
                cachedInputTokens: cachedInputTokens,
                outputTokens: outputTokens,
                turns: turns,
                chats: chats
            ),
            models: [],
            clients: []
        )
        let dataset = UsageAnalyticsDataset(
            requestedStart: start,
            requestedEnd: end,
            days: [day],
            fetchedAt: end,
            modelBreakdownIsPartial: false,
            clientBreakdownIsPartial: false
        )
        return UsageAnalyticsProjection.make(
            dataset: dataset,
            range: .days30,
            referenceDate: end,
            calendar: calendar
        )!
    }

    private func textValues(in view: NSView) -> [String] {
        view.subviews.flatMap { child in
            (child as? NSTextField).map { [$0.stringValue] } ?? textValues(in: child)
        }
    }
}
