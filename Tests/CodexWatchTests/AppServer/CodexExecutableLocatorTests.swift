import Foundation
import XCTest
@testable import CodexWatch

final class CodexExecutableLocatorTests: XCTestCase {
    func testExplicitExecutableWinsBeforeStandardLocations() throws {
        let explicit = URL(fileURLWithPath: "/private/tmp/injected-codex")
        let available = Set([
            explicit.path,
            "/Applications/ChatGPT.app/Contents/Resources/codex"
        ])
        let locator = CodexExecutableLocator(
            explicitURL: explicit,
            isExecutableFile: { available.contains($0.path) }
        )

        XCTAssertEqual(try locator.locate(), explicit)
    }

    func testStandardLocationsHaveDeterministicPriority() throws {
        let available = Set([
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ])
        let locator = CodexExecutableLocator(
            isExecutableFile: { available.contains($0.path) }
        )

        XCTAssertEqual(
            try locator.locate().path,
            "/Applications/Codex.app/Contents/Resources/codex"
        )
    }

    func testUnavailableExecutableReturnsTypedError() {
        let locator = CodexExecutableLocator(isExecutableFile: { _ in false })

        XCTAssertThrowsError(try locator.locate()) { error in
            XCTAssertEqual(error as? CodexExecutableLocatorError, .unavailable)
        }
    }
}
