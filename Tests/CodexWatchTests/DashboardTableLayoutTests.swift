import CoreGraphics
import XCTest
@testable import CodexWatch

final class DashboardTableLayoutTests: XCTestCase {
    func testMinimumWindowKeepsModelTableVisibleAndContainsClientOverflow() {
        let minimumViewportWidth: CGFloat = 692

        XCTAssertEqual(
            DashboardTableLayout.modelActivity.placement(in: minimumViewportWidth),
            .fits(contentWidth: 608)
        )
        XCTAssertEqual(
            DashboardTableLayout.clientTokens.placement(in: minimumViewportWidth),
            .horizontallyScrollable(contentWidth: 762)
        )
    }
}
