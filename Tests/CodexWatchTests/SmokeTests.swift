import XCTest
@testable import CodexWatch

final class SmokeTests: XCTestCase {
    func testApplicationIdentifierIsStable() {
        XCTAssertEqual(AppIdentity.bundleIdentifier, "com.moebis.codexwatch")
    }
}
