import Foundation
import XCTest
@testable import CodexWatch

final class CodexProfileStatsTests: XCTestCase {
    func testCompleteProfileDecodesExactServerStatistics() throws {
        let response = try JSONDecoder().decode(
            CodexProfileResponseDTO.self,
            from: Data(contentsOf: fixtureURL("profile-stats-complete.json"))
        )
        let fetchedAt = ISO8601DateFormatter().date(from: "2026-08-20T12:00:00Z")!
        let profile = try XCTUnwrap(response.profileStats(fetchedAt: fetchedAt))

        XCTAssertEqual(profile.lifetimeTokens, 30_300_000_000)
        XCTAssertEqual(profile.peakDailyTokens, 1_100_000_000)
        XCTAssertEqual(profile.longestRunningTurnSeconds, 56_580)
        XCTAssertEqual(profile.currentStreakDays, 42)
        XCTAssertEqual(profile.longestStreakDays, 82)
        XCTAssertEqual(profile.dailyBuckets.map(\.tokens), [125_000_000, 250_000_000])
        XCTAssertEqual(profile.dailyBuckets.map(\.date), [day("2026-08-18"), day("2026-08-19")])
        XCTAssertEqual(profile.insights.fastModePercent, 7)
        XCTAssertEqual(profile.insights.reasoningEffort, "Extra High")
        XCTAssertEqual(profile.insights.reasoningEffortPercent, 60)
        XCTAssertEqual(profile.insights.uniqueSkillsUsed, 82)
        XCTAssertEqual(profile.insights.totalSkillsUsed, 8_369)
        XCTAssertEqual(profile.insights.totalChats, 6_316)
        XCTAssertEqual(profile.invocations.map(\.displayName), ["superpowers:brainstorming", "browser"])
        XCTAssertEqual(profile.invocations.map(\.usageCount), [6_122, 525])
        XCTAssertEqual(profile.invocations.map(\.kind), [.skill, .plugin])
        XCTAssertEqual(profile.fetchedAt, fetchedAt)
    }

    func testInvalidOptionalFieldsDoNotFabricateValuesOrDiscardLifetimeTotal() throws {
        let response = try JSONDecoder().decode(
            CodexProfileResponseDTO.self,
            from: Data(contentsOf: fixtureURL("profile-stats-partial.json"))
        )
        let profile = try XCTUnwrap(response.profileStats())

        XCTAssertEqual(profile.lifetimeTokens, 30_300_000_000)
        XCTAssertNil(profile.peakDailyTokens)
        XCTAssertNil(profile.longestRunningTurnSeconds)
        XCTAssertEqual(profile.currentStreakDays, 42)
        XCTAssertNil(profile.longestStreakDays)
        XCTAssertTrue(profile.dailyBuckets.isEmpty)
        XCTAssertNil(profile.insights.fastModePercent)
        XCTAssertNil(profile.insights.reasoningEffort)
        XCTAssertNil(profile.insights.reasoningEffortPercent)
        XCTAssertNil(profile.insights.uniqueSkillsUsed)
        XCTAssertEqual(profile.insights.totalSkillsUsed, 8_369)
        XCTAssertEqual(profile.insights.totalChats, 6_316)
        XCTAssertEqual(profile.invocations.map(\.displayName), ["browser"])
    }

    func testDuplicateOrInvalidDailyBucketsRejectTheSeries() throws {
        for json in [
            #"{"stats":{"lifetime_tokens":1,"daily_usage_buckets":[{"start_date":"2026-08-19","tokens":2},{"start_date":"2026-08-19","tokens":3}]}}"#,
            #"{"stats":{"lifetime_tokens":1,"daily_usage_buckets":[{"start_date":"2026-02-30","tokens":2}]}}"#,
            #"{"stats":{"lifetime_tokens":1,"daily_usage_buckets":[{"start_date":"2026-08-19","tokens":-2}]}}"#
        ] {
            let response = try JSONDecoder().decode(
                CodexProfileResponseDTO.self,
                from: Data(json.utf8)
            )
            let profile = try XCTUnwrap(response.profileStats())

            XCTAssertEqual(profile.lifetimeTokens, 1)
            XCTAssertTrue(profile.dailyBuckets.isEmpty)
        }
    }

    func testOverflowAndWrongTypesRemainUnavailable() throws {
        let response = try JSONDecoder().decode(
            CodexProfileResponseDTO.self,
            from: Data(
                #"{"stats":{"lifetime_tokens":9223372036854775808,"peak_daily_tokens":"many","current_streak_days":999999999999999999999}}"#.utf8
            )
        )
        let profile = try XCTUnwrap(response.profileStats())

        XCTAssertNil(profile.lifetimeTokens)
        XCTAssertNil(profile.peakDailyTokens)
        XCTAssertNil(profile.currentStreakDays)
    }

    func testMissingStatsDoesNotCreateAnEmptyProfile() throws {
        let response = try JSONDecoder().decode(
            CodexProfileResponseDTO.self,
            from: Data(#"{"profile":{"display_name":"Ignored"}}"#.utf8)
        )

        XCTAssertNil(response.profileStats())
    }

    func testProfileDatesUseFixedPOSIXGregorianSemantics() throws {
        let parsed = try XCTUnwrap(CodexProfileDateParser.parse("2026-08-19"))

        XCTAssertEqual(parsed, day("2026-08-19"))
        XCTAssertEqual(CodexProfileDateParser.calendar.identifier, .gregorian)
        XCTAssertEqual(CodexProfileDateParser.calendar.locale?.identifier, "en_US_POSIX")
        XCTAssertEqual(CodexProfileDateParser.calendar.timeZone.secondsFromGMT(), 0)
    }

    func testTopInvocationsAreBoundedAfterRanking() throws {
        let entries = (1 ... 75).map { index in
            #"{"plugin_id":"\#(index)","plugin_name":"plugin-\#(index)","type":"plugin","usage_count":\#(index)}"#
        }.joined(separator: ",")
        let response = try JSONDecoder().decode(
            CodexProfileResponseDTO.self,
            from: Data(#"{"stats":{"top_invocations":[\#(entries)]}}"#.utf8)
        )

        let profile = try XCTUnwrap(response.profileStats())

        XCTAssertEqual(profile.invocations.count, CodexProfileResponseDTO.maximumInvocationCount)
        XCTAssertEqual(profile.invocations.first?.usageCount, 75)
        XCTAssertEqual(profile.invocations.last?.usageCount, 26)
    }

    func testEqualInvocationRanksHaveATotalDeterministicOrder() throws {
        let response = try JSONDecoder().decode(
            CodexProfileResponseDTO.self,
            from: Data(
                #"{"stats":{"top_invocations":[{"plugin_id":"lower","plugin_name":"alpha","type":"plugin","usage_count":10},{"plugin_id":"upper","plugin_name":"ALPHA","type":"plugin","usage_count":10}]}}"#.utf8
            )
        )

        let profile = try XCTUnwrap(response.profileStats())

        XCTAssertEqual(profile.invocations.map(\.displayName), ["ALPHA", "alpha"])
        XCTAssertEqual(profile.invocations.map(\.id), ["plugin:upper", "plugin:lower"])
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func day(_ text: String) -> Date {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        return utcCalendar().date(from: DateComponents(
            year: parts[0],
            month: parts[1],
            day: parts[2]
        ))!
    }

    private func fixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(name)
    }
}
