import Foundation
import XCTest
@testable import CodexWatch

final class UsageCapabilityTests: XCTestCase {
    func testAdditionalLimitsDoNotReplaceBaseWeeklyQuota() throws {
        let snapshot = try fixtureSnapshot()

        XCTAssertEqual(snapshot.weeklyWindow?.id, "primary")
        XCTAssertEqual(snapshot.weeklyWindow?.remainingPercent, 68)
        XCTAssertEqual(snapshot.additionalWindows.map(\.id), ["codex-spark", "codex-spark-weekly"])
        XCTAssertEqual(snapshot.additionalWindows.map(\.title), [
            "Codex Spark 5-hour",
            "Codex Spark Weekly"
        ])
        XCTAssertEqual(snapshot.additionalWindows.map(\.window.kind), [.rolling(hours: 5), .weekly])
        XCTAssertEqual(MenuBarText.statusTitle(snapshot: snapshot), "68%")
    }

    func testMalformedOptionalCapabilityPreservesValidSiblings() throws {
        let snapshot = try fixtureSnapshot()

        XCTAssertEqual(snapshot.windows.count, 1)
        XCTAssertEqual(snapshot.additionalWindows.count, 2)
        XCTAssertEqual(snapshot.availableResetCredits, 2)
        XCTAssertEqual(snapshot.codeReviewWindows.map(\.window.kind), [.daily])
        XCTAssertEqual(snapshot.codeReviewWindows.first?.window.remainingPercent, 90)
        XCTAssertEqual(snapshot.spendControl?.limit, Decimal(1000))
        XCTAssertEqual(snapshot.spendControl?.used, Decimal(string: "36.5"))
        XCTAssertEqual(snapshot.spendControl?.remainingPercent, 96.35)
    }

    func testMalformedPrimaryWindowDoesNotDiscardValidWeeklySibling() throws {
        let snapshot = try JSONDecoder().decode(
            UsageResponseDTO.self,
            from: Data(
                #"{"rate_limit":{"primary_window":{"used_percent":"bad","limit_window_seconds":18000},"secondary_window":{"used_percent":22,"limit_window_seconds":604800}}}"#.utf8
            )
        ).snapshot()

        XCTAssertEqual(snapshot.windows.map(\.id), ["secondary"])
        XCTAssertEqual(snapshot.weeklyWindow?.remainingPercent, 78)
    }

    func testResetCreditDetailsReturnTheFullValidatedInventory() throws {
        let response = try JSONDecoder().decode(
            ResetCreditDetailsDTO.self,
            from: Data(
                #"{"credits":[{"id":"credit-b","status":"available","title":"Second reset","granted_at":"2029-12-04T08:30:45Z","expires_at":"2030-01-03T08:30:45Z","is_supported_by_plan":true},{"id":"credit-a","status":"available","title":"First reset","granted_at":"2029-12-03T08:30:45Z","expires_at":"2030-01-02T08:30:45Z","is_supported_by_plan":true},{"id":"bad-credit","status":"available","granted_at":"invalid","expires_at":"2030-01-01T08:30:45Z"}]}"#.utf8
            )
        )

        let inventory = response.inventory()

        XCTAssertEqual(inventory.map(\.id), ["credit-b", "credit-a"])
        XCTAssertEqual(inventory.map(\.title), ["Second reset", "First reset"])
        XCTAssertEqual(inventory.map(\.status), ["available", "available"])
    }

    func testUnknownLimitUsesBoundedStableSlug() throws {
        let longName = "  Future / Model " + String(repeating: "X", count: 100)
        let json = """
        {
          "additional_rate_limits": [{
            "limit_name": "\(longName)",
            "rate_limit": {
              "primary_window": {
                "used_percent": 12,
                "limit_window_seconds": 18000
              }
            }
          }]
        }
        """

        let snapshot = try JSONDecoder().decode(
            UsageResponseDTO.self,
            from: Data(json.utf8)
        ).snapshot()

        let id = try XCTUnwrap(snapshot.additionalWindows.first?.id)
        XCTAssertTrue(id.hasPrefix("codex-"))
        XCTAssertLessThanOrEqual(id.utf8.count, 64)
        XCTAssertNotNil(id.range(of: #"^[a-z0-9-]+$"#, options: .regularExpression))
    }

    private func fixtureSnapshot() throws -> UsageSnapshot {
        let data = try Data(contentsOf: fixtureURL("usage-additional-limits.json"))
        return try JSONDecoder().decode(UsageResponseDTO.self, from: data).snapshot(
            fetchedAt: Date(timeIntervalSince1970: 2_000_000_000)
        )
    }

    private func fixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(name)
    }
}
