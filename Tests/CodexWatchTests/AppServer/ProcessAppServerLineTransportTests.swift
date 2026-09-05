import Foundation
import XCTest
@testable import CodexWatch

final class ProcessAppServerLineTransportTests: XCTestCase {
    func testShortLineArrivesWhileChildKeepsPipeOpen() async throws {
        let helper = try helperScript("""
        printf '%s\\n' '{"ok":true}'
        IFS= read -r line
        """)
        defer { try? FileManager.default.removeItem(at: helper.deletingLastPathComponent()) }
        let received = expectation(description: "Short reply without waiting for EOF or a full buffer")
        let transport = ProcessAppServerLineTransport(executableURL: helper)
        try await transport.start(receiveLine: { line in
            XCTAssertEqual(String(data: line, encoding: .utf8), #"{"ok":true}"#)
            received.fulfill()
        }, termination: { _ in })
        await fulfillment(of: [received], timeout: 2)
        await transport.stop()
    }

    func testOversizedChildOutputCleansUpThroughClientTermination() async throws {
        let helper = try helperScript("""
        IFS= read -r line
        printf '%s\\n' '{"id":1,"result":{"userAgent":"fixture","codexHome":"fixture","platformFamily":"unix","platformOs":"macos"}}'
        IFS= read -r line
        IFS= read -r line
        printf '%0512d\\n' 0
        IFS= read -r line
        """)
        defer { try? FileManager.default.removeItem(at: helper.deletingLastPathComponent()) }
        let transport = ProcessAppServerLineTransport(executableURL: helper, maximumLineBytes: 256)
        let client = CodexAppServerClient(
            transport: transport,
            clientInfo: AppServerClientInfo(name: "fixture", title: nil, version: "1"),
            requestTimeout: .seconds(2)
        )
        try await client.start()
        do {
            _ = try await client.readAccount()
            XCTFail("Expected oversized input to terminate the client")
        } catch {
            XCTAssertEqual(error as? AppServerError, .lineTooLarge(maxBytes: 256))
        }
        // stop must remain safe after the reader has already terminated the client.
        await client.stop()
        do {
            try await transport.send(Data("{}".utf8))
            XCTFail("Stopped transport retained an open child input")
        } catch {
            XCTAssertEqual(error as? AppServerError, .transportFailure)
        }
    }

    private func helperScript(_ body: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-watch-transport-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = directory.appendingPathComponent("fixture")
        try Data(("#!/bin/sh\n" + body + "\n").utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        return script
    }
}
