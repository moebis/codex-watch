import Foundation

protocol AppServerLineTransport: Sendable {
    func start(
        receiveLine: @escaping @Sendable (Data) async -> Void,
        termination: @escaping @Sendable (Error?) async -> Void
    ) async throws

    func send(_ line: Data) async throws
    func stop() async
}

enum AppServerError: Error, Equatable, Sendable {
    case notStarted
    case terminated
    case invalidIdempotencyKey
    case malformedMessage
    case lineTooLarge(maxBytes: Int)
    case invalidResponse
    case remoteError(code: Int)
    case transportFailure
    case timedOut
}
