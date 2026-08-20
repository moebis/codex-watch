import Foundation
import XCTest
@testable import CodexWatch

final class UsageAnalyticsDatasetTests: XCTestCase {
    func testDatasetPreservesObservedDatesAndPartialBreakdowns() throws {
        let data = try Data(contentsOf: fixtureURL("usage-analytics-365-partial.json"))
        let calendar = utcCalendar()
        let start = day("2025-08-21")
        let end = day("2026-08-20")
        let fetchedAt = day("2026-08-20")

        let dataset = try XCTUnwrap(
            JSONDecoder().decode(UsageAnalyticsResponseDTO.self, from: data).dataset(
                requestedStart: start,
                requestedEnd: end,
                calendar: calendar,
                fetchedAt: fetchedAt
            )
        )

        XCTAssertEqual(dataset.days.map(\.date), [day("2026-08-18"), day("2026-08-19")])
        XCTAssertEqual(dataset.dataThrough, day("2026-08-19"))
        XCTAssertEqual(dataset.days[0].totals.totalTokens, 60)
        XCTAssertTrue(dataset.modelBreakdownIsPartial)
        XCTAssertFalse(dataset.clientBreakdownIsPartial)
        XCTAssertEqual(dataset.days[0].models.map(\.model), ["gpt-5.6-sol"])
        XCTAssertEqual(dataset.days[1].models.first?.credits, Decimal(string: "2.75"))
        XCTAssertEqual(dataset.days[0].clients.map(\.clientID), ["CODEX_DESKTOP_APP"])
    }

    func testDuplicateDailyRowsRejectWholeDataset() throws {
        let response = try JSONDecoder().decode(
            UsageAnalyticsResponseDTO.self,
            from: Data(
                #"{"group_by":"day","data":[{"date":"2026-08-19","totals":{"threads":1,"turns":1,"uncached_text_input_tokens":1,"cached_text_input_tokens":1,"text_output_tokens":1,"text_total_tokens":3}},{"date":"2026-08-19","totals":{"threads":1,"turns":1,"uncached_text_input_tokens":1,"cached_text_input_tokens":1,"text_output_tokens":1,"text_total_tokens":3}}]}"#.utf8
            )
        )

        XCTAssertNil(response.dataset(
            requestedStart: day("2026-08-01"),
            requestedEnd: day("2026-08-20"),
            calendar: utcCalendar()
        ))
    }

    func testInvalidNestedClientIsSkippedAndMarksOnlyClientBreakdownPartial() throws {
        let response = try JSONDecoder().decode(
            UsageAnalyticsResponseDTO.self,
            from: Data(
                #"{"group_by":"day","data":[{"date":"2026-08-19","totals":{"threads":1,"turns":1,"uncached_text_input_tokens":1,"cached_text_input_tokens":1,"text_output_tokens":1,"text_total_tokens":3},"models":[],"clients":[{"client_id":"CODEX_CLI","threads":1,"turns":1,"uncached_text_input_tokens":1,"cached_text_input_tokens":1,"text_output_tokens":1,"text_total_tokens":3},{"client_id":"broken","threads":-1}]}]}"#.utf8
            )
        )

        let dataset = try XCTUnwrap(response.dataset(
            requestedStart: day("2026-08-01"),
            requestedEnd: day("2026-08-20"),
            calendar: utcCalendar()
        ))

        XCTAssertEqual(dataset.days.first?.clients.map(\.clientID), ["CODEX_CLI"])
        XCTAssertFalse(dataset.modelBreakdownIsPartial)
        XCTAssertTrue(dataset.clientBreakdownIsPartial)
    }

    func testEmptyDailyArrayIsAValidDatasetWithNoObservedDates() throws {
        let response = try JSONDecoder().decode(
            UsageAnalyticsResponseDTO.self,
            from: Data(#"{"group_by":"day","data":[]}"#.utf8)
        )

        let dataset = try XCTUnwrap(response.dataset(
            requestedStart: day("2026-08-01"),
            requestedEnd: day("2026-08-20"),
            calendar: utcCalendar()
        ))

        XCTAssertTrue(dataset.days.isEmpty)
        XCTAssertNil(dataset.dataThrough)
    }

    func testActivityOnlyDailyRowIsPreservedWithoutFabricatingTokenUsage() throws {
        let response = try JSONDecoder().decode(
            UsageAnalyticsResponseDTO.self,
            from: Data(
                #"{"group_by":"day","data":[{"date":"2026-01-15","totals":{"threads":2,"turns":5,"credits":1.5,"users":1},"models":[],"clients":[]}] }"#.utf8
            )
        )

        let dataset = try XCTUnwrap(response.dataset(
            requestedStart: day("2026-01-01"),
            requestedEnd: day("2026-08-20"),
            calendar: utcCalendar()
        ))

        let activityOnly = try XCTUnwrap(dataset.days.first)
        XCTAssertFalse(activityOnly.tokenDataIsAvailable)
        XCTAssertEqual(activityOnly.totals.turns, 5)
        XCTAssertEqual(activityOnly.totals.chats, 2)
        XCTAssertEqual(activityOnly.totals.totalTokens, 0)
    }

    func testInvalidOrOutOfRangeDailyTotalsRejectWholeDataset() throws {
        let invalidRows = [
            #"{"date":"2026-07-31","totals":{"threads":1,"turns":1,"uncached_text_input_tokens":1,"cached_text_input_tokens":1,"text_output_tokens":1,"text_total_tokens":3}}"#,
            #"{"date":"2026-08-19","totals":{"threads":1,"turns":-1,"uncached_text_input_tokens":1,"cached_text_input_tokens":1,"text_output_tokens":1,"text_total_tokens":3}}"#,
            #"{"date":"2026-08-19","totals":{"threads":1,"turns":1,"cached_text_input_tokens":1,"text_output_tokens":1,"text_total_tokens":3}}"#
        ]

        for row in invalidRows {
            let response = try JSONDecoder().decode(
                UsageAnalyticsResponseDTO.self,
                from: Data("{\"group_by\":\"day\",\"data\":[\(row)]}".utf8)
            )
            XCTAssertNil(response.dataset(
                requestedStart: day("2026-08-01"),
                requestedEnd: day("2026-08-20"),
                calendar: utcCalendar()
            ))
        }
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

    private func fixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(name)
    }
}
