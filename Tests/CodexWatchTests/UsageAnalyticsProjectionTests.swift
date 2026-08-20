import Foundation
import XCTest
@testable import CodexWatch

final class UsageAnalyticsProjectionTests: XCTestCase {
    func testThirtyDayProjectionReportsCoverageAndDataThrough() throws {
        let dataset = makeDataset(observed: [
            makeDay("2026-08-18", total: 10, turns: 2, chats: 1),
            makeDay("2026-08-19", total: 20, turns: 3, chats: 2)
        ])

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
        let complete = makeComparisonDataset(missingCurrentDays: 0)
        let projection = try XCTUnwrap(UsageAnalyticsProjection.make(
            dataset: complete,
            range: .days7,
            referenceDate: day("2026-08-20"),
            calendar: utcCalendar()
        ))

        guard case let .percent(change)? = projection.comparison else {
            return XCTFail("Expected a percentage comparison")
        }
        XCTAssertEqual(change, 0.20, accuracy: 0.0001)

        let incomplete = makeComparisonDataset(missingCurrentDays: 1)
        XCTAssertNil(UsageAnalyticsProjection.make(
            dataset: incomplete,
            range: .days7,
            referenceDate: day("2026-08-20"),
            calendar: utcCalendar()
        )?.comparison)
    }

    func testModelsUseActivityWhileClientsUseTokens() throws {
        let analyticsDay = UsageAnalyticsDay(
            date: day("2026-08-20"),
            totals: totals(total: 1_000, turns: 10, chats: 3),
            models: [
                UsageModelActivity(model: "gpt-5.6-sol", turns: 8, chats: 2, credits: 3.5),
                UsageModelActivity(model: "gpt-5.6-terra", turns: 2, chats: 1, credits: 0.5)
            ],
            clients: [
                UsageClientActivity(
                    clientID: "CODEX_DESKTOP_APP",
                    totals: totals(total: 900, turns: 9, chats: 3)
                )
            ]
        )

        let projection = try XCTUnwrap(UsageAnalyticsProjection.make(
            dataset: makeDataset(observed: [analyticsDay]),
            range: .days7,
            referenceDate: day("2026-08-20"),
            calendar: utcCalendar()
        ))

        XCTAssertEqual(projection.models.first?.model, "gpt-5.6-sol")
        XCTAssertEqual(projection.models.first?.turns, 8)
        XCTAssertEqual(try XCTUnwrap(projection.models.first?.turnShare), 0.8, accuracy: 0.0001)
        XCTAssertEqual(projection.clients.first?.clientID, "CODEX_DESKTOP_APP")
        XCTAssertEqual(projection.clients.first?.totalTokens, 900)
    }

    func testMissingAndObservedZeroDaysRemainDistinct() throws {
        let projection = try XCTUnwrap(UsageAnalyticsProjection.make(
            dataset: makeDataset(observed: [makeDay("2026-08-19", total: 0, turns: 0, chats: 0)]),
            range: .days7,
            referenceDate: day("2026-08-20"),
            calendar: utcCalendar()
        ))

        XCTAssertEqual(projection.days.count, 7)
        XCTAssertEqual(projection.days[5].state, .observed(totals(total: 0, turns: 0, chats: 0)))
        XCTAssertEqual(projection.days[6].state, .missing)
    }

    func testAggregateOverflowRejectsProjection() {
        let dataset = makeDataset(observed: [
            makeDay("2026-08-19", total: .max, turns: 1, chats: 1),
            makeDay("2026-08-20", total: 1, turns: 1, chats: 1)
        ])

        XCTAssertNil(UsageAnalyticsProjection.make(
            dataset: dataset,
            range: .days7,
            referenceDate: day("2026-08-20"),
            calendar: utcCalendar()
        ))
    }

    func testThreeHundredSixtyFiveDayRangeNeverClaimsComparison() throws {
        let projection = try XCTUnwrap(UsageAnalyticsProjection.make(
            dataset: makeDataset(observed: [makeDay("2026-08-20", total: 10, turns: 1, chats: 1)]),
            range: .days365,
            referenceDate: day("2026-08-20"),
            calendar: utcCalendar()
        ))

        XCTAssertNil(projection.comparison)
    }

    private func makeComparisonDataset(missingCurrentDays: Int) -> UsageAnalyticsDataset {
        let previousDates = (0 ..< 7).map { offset in
            utcCalendar().date(byAdding: .day, value: offset, to: day("2026-08-07"))!
        }
        let currentDates = (0 ..< (7 - missingCurrentDays)).map { offset in
            utcCalendar().date(byAdding: .day, value: offset, to: day("2026-08-14"))!
        }
        let previousValues: [Int64] = [10, 10, 10, 10, 10, 10, 40]
        let currentValues: [Int64] = [20, 20, 20, 20, 20, 10, 10]
        let previous = zip(previousDates, previousValues).map { date, total in
            makeDay(date, total: total, turns: 1, chats: 1)
        }
        let current = zip(currentDates, currentValues).map { date, total in
            makeDay(date, total: total, turns: 1, chats: 1)
        }
        return makeDataset(observed: previous + current)
    }

    private func makeDataset(observed: [UsageAnalyticsDay]) -> UsageAnalyticsDataset {
        UsageAnalyticsDataset(
            requestedStart: day("2025-08-21"),
            requestedEnd: day("2026-08-20"),
            days: observed.sorted { $0.date < $1.date },
            fetchedAt: day("2026-08-20"),
            modelBreakdownIsPartial: false,
            clientBreakdownIsPartial: false
        )
    }

    private func makeDay(
        _ text: String,
        total: Int64,
        turns: Int64,
        chats: Int64
    ) -> UsageAnalyticsDay {
        makeDay(day(text), total: total, turns: turns, chats: chats)
    }

    private func makeDay(
        _ date: Date,
        total: Int64,
        turns: Int64,
        chats: Int64
    ) -> UsageAnalyticsDay {
        UsageAnalyticsDay(
            date: date,
            totals: totals(total: total, turns: turns, chats: chats),
            models: [],
            clients: []
        )
    }

    private func totals(total: Int64, turns: Int64, chats: Int64) -> UsageTokenTotals {
        UsageTokenTotals(
            totalTokens: total,
            uncachedInputTokens: total,
            cachedInputTokens: 0,
            outputTokens: 0,
            turns: turns,
            chats: chats
        )
    }

    private func day(_ text: String) -> Date {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        return utcCalendar().date(from: DateComponents(
            year: parts[0],
            month: parts[1],
            day: parts[2]
        ))!
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
