import Foundation

protocol AppServerAccountServing: Sendable {
    func start() async throws
    func readAccount() async throws -> AppServerAccountResponse
    func readRateLimits() async throws -> AppServerRateLimitsResponse
    func readAccountUsage() async throws -> AppServerAccountUsageResponse
    func consumeRateLimitReset(
        idempotencyKey: String,
        creditID: String?
    ) async throws -> AppServerResetOutcome
    func rateLimitUpdates() async -> AsyncStream<AppServerRateLimitSnapshot>
    func stop() async
}

extension CodexAppServerClient: AppServerAccountServing {}

enum CodexAccountServiceError: Error, Equatable, Sendable {
    case signInRequired
    case unavailable
}

protocol CodexAccountServing: Sendable {
    func fetchQuota(fetchedAt: Date) async throws -> UsageSnapshot
    func fetchProfile(fetchedAt: Date) async throws -> CodexProfileStats
    func consumeReset(
        idempotencyKey: String,
        creditID: String?
    ) async throws -> AppServerResetOutcome
    func rateLimitUpdates() async throws -> AsyncStream<AppServerRateLimitSnapshot>
    func stop() async
}

actor CodexAccountService: CodexAccountServing {
    private let client: any AppServerAccountServing
    private var isStarted = false
    private var isChatGPTAccount = false

    init(client: any AppServerAccountServing) {
        self.client = client
    }

    static func makeDefault(clientVersion: String) -> CodexAccountService? {
        guard let transport = try? ProcessAppServerLineTransport(
            locator: CodexExecutableLocator()
        ) else { return nil }
        let client = CodexAppServerClient(
            transport: transport,
            clientInfo: AppServerClientInfo(
                name: "codex-watch",
                title: "Codex Watch",
                version: clientVersion
            )
        )
        return CodexAccountService(client: client)
    }

    func fetchQuota(fetchedAt: Date) async throws -> UsageSnapshot {
        try await prepareChatGPTAccount()
        do {
            let response = try await client.readRateLimits()
            return AppServerUsageAdapter.snapshot(from: response, fetchedAt: fetchedAt)
        } catch let error as CodexAccountServiceError {
            throw error
        } catch {
            throw CodexAccountServiceError.unavailable
        }
    }

    func fetchProfile(fetchedAt: Date) async throws -> CodexProfileStats {
        try await prepareChatGPTAccount()
        do {
            let response = try await client.readAccountUsage()
            return AppServerUsageAdapter.profile(from: response, fetchedAt: fetchedAt)
        } catch let error as CodexAccountServiceError {
            throw error
        } catch {
            throw CodexAccountServiceError.unavailable
        }
    }

    func consumeReset(
        idempotencyKey: String,
        creditID: String?
    ) async throws -> AppServerResetOutcome {
        try await prepareChatGPTAccount()
        do {
            return try await client.consumeRateLimitReset(
                idempotencyKey: idempotencyKey,
                creditID: creditID
            )
        } catch let error as AppServerError {
            throw error
        } catch {
            throw CodexAccountServiceError.unavailable
        }
    }

    func rateLimitUpdates() async throws -> AsyncStream<AppServerRateLimitSnapshot> {
        try await prepareChatGPTAccount()
        return await client.rateLimitUpdates()
    }

    func stop() async {
        isStarted = false
        isChatGPTAccount = false
        await client.stop()
    }

    private func prepareChatGPTAccount() async throws {
        if isStarted, isChatGPTAccount { return }
        do {
            if !isStarted {
                try await client.start()
                isStarted = true
            }
            let response = try await client.readAccount()
            guard case .chatGPT = response.account else {
                throw CodexAccountServiceError.signInRequired
            }
            isChatGPTAccount = true
        } catch let error as CodexAccountServiceError {
            throw error
        } catch {
            throw CodexAccountServiceError.unavailable
        }
    }
}
