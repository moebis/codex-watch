import Foundation
import XCTest
@testable import CodexWatch

final class UsageHeatmapLayoutTests: XCTestCase {
    func testChronologicalDaysMapDownWeekdayRowsThenAcrossWeekColumns() throws {
        let calendar = mondayFirstCalendar()
        let days = (19 ... 25).map { dayNumber in
            UsageDayCell(
                date: day("2026-08-\(dayNumber)"),
                state: .missing
            )
        }

        let layout = UsageHeatmapLayout(days: days, calendar: calendar)

        XCTAssertEqual(layout.leadingPaddingCount, 2)
        XCTAssertEqual(layout.columnCount, 2)
        XCTAssertEqual(layout.slots.count, 14)
        XCTAssertNil(layout.slots[0].day)
        XCTAssertNil(layout.slots[1].day)
        XCTAssertEqual(layout.cells[0].row, 2)
        XCTAssertEqual(layout.cells[0].column, 0)
        XCTAssertEqual(layout.cells[4].row, 6)
        XCTAssertEqual(layout.cells[4].column, 0)
        XCTAssertEqual(layout.cells[5].row, 0)
        XCTAssertEqual(layout.cells[5].column, 1)
        XCTAssertEqual(layout.cells[6].row, 1)
        XCTAssertEqual(layout.cells[6].column, 1)
    }

    func testLayoutPreservesMissingObservedZeroAndActivityOnlyDays() {
        let zeroTotals = UsageTokenTotals(
            totalTokens: 0,
            uncachedInputTokens: 0,
            cachedInputTokens: 0,
            outputTokens: 0,
            turns: 0,
            chats: 0
        )
        let days = [
            UsageDayCell(date: day("2026-08-17"), state: .missing),
            UsageDayCell(date: day("2026-08-18"), state: .observed(zeroTotals)),
            UsageDayCell(date: day("2026-08-19"), state: .activityOnly(turns: 3, chats: 2))
        ]

        let layout = UsageHeatmapLayout(days: days, calendar: mondayFirstCalendar())

        XCTAssertEqual(layout.cells.map(\.day), days)
        XCTAssertEqual(
            UsageHeatmapPresentation.accessibilityText(layout.cells[0].day),
            "Aug 17, 2026, missing"
        )
        XCTAssertEqual(
            UsageHeatmapPresentation.accessibilityText(layout.cells[1].day),
            "Aug 18, 2026, observed, 0 tokens"
        )
        XCTAssertEqual(
            UsageHeatmapPresentation.accessibilityText(layout.cells[2].day),
            "Aug 19, 2026, activity only, 3 turns, 2 chats, token totals unavailable"
        )
    }

    func testThreeHundredSixtyFiveDaysUseSevenRowsAndFiftyThreeWeekColumns() {
        let calendar = mondayFirstCalendar()
        let start = day("2026-08-19")
        let days = (0 ..< 365).map { offset in
            UsageDayCell(
                date: calendar.date(byAdding: .day, value: offset, to: start)!,
                state: .missing
            )
        }

        let layout = UsageHeatmapLayout(days: days, calendar: calendar)

        XCTAssertEqual(layout.leadingPaddingCount, 2)
        XCTAssertEqual(layout.columnCount, 53)
        XCTAssertEqual(layout.slots.count, 371)
        XCTAssertEqual(layout.cells[0].row, 2)
        XCTAssertEqual(layout.cells[0].column, 0)
        XCTAssertEqual(layout.cells[364].row, 2)
        XCTAssertEqual(layout.cells[364].column, 52)
    }

    private func day(_ value: String) -> Date {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        return mondayFirstCalendar().date(from: DateComponents(
            year: parts[0],
            month: parts[1],
            day: parts[2]
        ))!
    }

    private func mondayFirstCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }
}
