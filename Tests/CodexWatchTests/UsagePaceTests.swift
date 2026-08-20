import Foundation
import XCTest
@testable import CodexWatch

final class UsagePaceTests: XCTestCase {
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

    func testPaceProjectsExhaustionWhenObservedRateWillRunOutEarly() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let window = UsageWindow(
            id: "weekly",
            kind: .weekly,
            usedPercent: 75,
            resetAt: now.addingTimeInterval(3.5 * 86_400),
            durationSeconds: 7 * 86_400
        )

        let pace = try XCTUnwrap(UsagePace.calculate(window: window, now: now))

        XCTAssertFalse(pace.willLastToReset)
        XCTAssertEqual(
            try XCTUnwrap(pace.projectedExhaustion).timeIntervalSince(now),
            28 * 3_600,
            accuracy: 0.001
        )
    }
}
