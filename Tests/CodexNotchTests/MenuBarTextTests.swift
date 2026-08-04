import AppKit
import Foundation
import XCTest
@testable import CodexNotch

final class MenuBarTextTests: XCTestCase {
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
            "Sign in to ChatGPT to load quota"
        )
        XCTAssertEqual(
            MenuBarText.summary(snapshot: nil, error: .quotaUnavailable),
            "Quota unavailable"
        )
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

        XCTAssertEqual(presentation.quotaValue, "81%")
        XCTAssertEqual(try XCTUnwrap(presentation.quotaProgress), 0.81, accuracy: 0.0001)
        XCTAssertEqual(presentation.resetValue, "2d 0h")
        XCTAssertEqual(try XCTUnwrap(presentation.resetProgress), 2.0 / 7.0, accuracy: 0.0001)
        XCTAssertNotNil(presentation.resetDetail)
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

    private func textValues(in view: NSView) -> [String] {
        view.subviews.flatMap { child in
            (child as? NSTextField).map { [$0.stringValue] } ?? textValues(in: child)
        }
    }
}
