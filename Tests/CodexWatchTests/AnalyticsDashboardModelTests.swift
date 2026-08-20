import Foundation
import XCTest
@testable import CodexWatch

@MainActor
final class AnalyticsDashboardModelTests: XCTestCase {
    func testDashboardRestoresAndPersistsTopLevelSection() {
        let suiteName = "AnalyticsDashboardModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("lifetime", forKey: "codexWatch.analyticsSection")

        let model = AnalyticsDashboardModel(defaults: defaults, calendar: utcCalendar())

        XCTAssertEqual(model.section, .lifetime)
        model.section = .usage
        XCTAssertEqual(defaults.string(forKey: "codexWatch.analyticsSection"), "usage")
    }

    func testDashboardRestoresRangeAndReprojectsNewDataset() throws {
        let suiteName = "AnalyticsDashboardModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(90, forKey: "codexWatch.analyticsRange")
        let model = AnalyticsDashboardModel(defaults: defaults, calendar: utcCalendar())
        let now = day("2026-08-20")

        model.update(dataset: makeDashboardDataset(total: 100), error: nil, now: now)

        XCTAssertEqual(model.range, .days90)
        XCTAssertEqual(model.projection?.totalTokens, 100)

        model.range = .days7
        XCTAssertEqual(defaults.integer(forKey: "codexWatch.analyticsRange"), 7)
        XCTAssertEqual(model.projection?.range, .days7)
    }

    func testDashboardKeepsLastDatasetAndMarksAnalyticsStale() {
        let suiteName = "AnalyticsDashboardModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AnalyticsDashboardModel(defaults: defaults, calendar: utcCalendar())
        let now = day("2026-08-20")

        model.update(dataset: makeDashboardDataset(total: 100), error: nil, now: now)
        model.update(dataset: nil, error: .analyticsUnavailable, now: now)

        XCTAssertEqual(model.projection?.totalTokens, 100)
        XCTAssertTrue(model.isStale)
        XCTAssertEqual(model.errorState, .analyticsUnavailable)
    }

    func testDashboardCSVUsesCurrentSelectedRange() throws {
        let suiteName = "AnalyticsDashboardModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AnalyticsDashboardModel(defaults: defaults, calendar: utcCalendar())
        let now = day("2026-08-20")
        model.update(dataset: makeDashboardDataset(total: 100), error: nil, now: now)
        model.range = .days7

        XCTAssertTrue(try model.csvString().hasPrefix("Codex Watch analytics,7d\r\n"))
        XCTAssertEqual(
            model.suggestedCSVFilename,
            "codex-watch-analytics-7d-2026-08-20.csv"
        )
    }

    func testDashboardKeepsProfileAndMarksOnlyProfileSurfaceStale() {
        let suiteName = "AnalyticsDashboardModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AnalyticsDashboardModel(defaults: defaults, calendar: utcCalendar())
        let now = day("2026-08-20")
        let profile = makeProfile(total: 30_300_000_000, fetchedAt: now)

        model.update(
            dataset: makeDashboardDataset(total: 100),
            error: nil,
            profileStats: profile,
            profileError: nil,
            now: now
        )
        model.update(
            dataset: makeDashboardDataset(total: 200),
            error: nil,
            profileStats: nil,
            profileError: .profileUnavailable,
            now: now
        )

        XCTAssertEqual(model.projection?.totalTokens, 200)
        XCTAssertFalse(model.isStale)
        XCTAssertEqual(model.lifetime?.lifetimeTokens, "30.3B")
        XCTAssertTrue(model.profileIsStale)
        XCTAssertEqual(model.profileErrorState, .profileUnavailable)
    }

    private func makeDashboardDataset(total: Int64) -> UsageAnalyticsDataset {
        let end = day("2026-08-20")
        let start = utcCalendar().date(byAdding: .day, value: -364, to: end)!
        return UsageAnalyticsDataset(
            requestedStart: start,
            requestedEnd: end,
            days: [UsageAnalyticsDay(
                date: end,
                totals: UsageTokenTotals(
                    totalTokens: total,
                    uncachedInputTokens: total,
                    cachedInputTokens: 0,
                    outputTokens: 0,
                    turns: 1,
                    chats: 1
                ),
                models: [],
                clients: []
            )],
            fetchedAt: end,
            modelBreakdownIsPartial: false,
            clientBreakdownIsPartial: false
        )
    }

    private func makeProfile(total: Int64, fetchedAt: Date) -> CodexProfileStats {
        CodexProfileStats(
            lifetimeTokens: total,
            peakDailyTokens: nil,
            longestRunningTurnSeconds: nil,
            currentStreakDays: nil,
            longestStreakDays: nil,
            dailyBuckets: [],
            insights: CodexProfileInsights(
                fastModePercent: nil,
                reasoningEffort: nil,
                reasoningEffortPercent: nil,
                uniqueSkillsUsed: nil,
                totalSkillsUsed: nil,
                totalChats: nil
            ),
            invocations: [],
            fetchedAt: fetchedAt
        )
    }

    private func day(_ value: String) -> Date {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        return utcCalendar().date(from: DateComponents(
            year: parts[0],
            month: parts[1],
            day: parts[2]
        ))!
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
