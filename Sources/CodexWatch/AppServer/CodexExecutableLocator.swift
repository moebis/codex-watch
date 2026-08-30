import Foundation

enum CodexExecutableLocatorError: Error, Equatable, Sendable {
    case unavailable
}

struct CodexExecutableLocator: Sendable {
    typealias ExecutableCheck = @Sendable (URL) -> Bool

    private static let standardURLs = [
        URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex"),
        URL(fileURLWithPath: "/Applications/Codex.app/Contents/Resources/codex"),
        URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
        URL(fileURLWithPath: "/usr/local/bin/codex")
    ]

    private let explicitURL: URL?
    private let isExecutableFile: ExecutableCheck

    init(
        explicitURL: URL? = nil,
        isExecutableFile: @escaping ExecutableCheck = {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }
    ) {
        self.explicitURL = explicitURL
        self.isExecutableFile = isExecutableFile
    }

    func locate() throws -> URL {
        let candidates = explicitURL.map { [$0] } ?? []
        for candidate in candidates + Self.standardURLs where isExecutableFile(candidate) {
            return candidate
        }
        throw CodexExecutableLocatorError.unavailable
    }
}
