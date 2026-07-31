import Foundation

enum CodexUsageError: Error, Equatable {
    case reauthenticationRequired
    case invalidHTTPResponse
    case httpStatus(Int)
    case decodingFailed
}

enum SecureUsageSession {
    static func make() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        return URLSession(
            configuration: configuration,
            delegate: SameHostHTTPSRedirectDelegate(),
            delegateQueue: nil
        )
    }
}

private final class SameHostHTTPSRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard request.url?.scheme == "https",
              request.url?.host == task.originalRequest?.url?.host else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

struct CodexUsageClient {
    static let defaultEndpoint = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    static let resetCreditsPath = "/backend-api/wham/rate-limit-reset-credits"

    let credentials: CodexCredentials
    let session: URLSession
    let endpoint: URL
    let resetCreditsEndpoint: URL

    init(credentials: CodexCredentials,
         session: URLSession = SecureUsageSession.make(),
         endpoint: URL = CodexUsageClient.defaultEndpoint,
         resetCreditsEndpoint: URL? = nil) {
        self.credentials = credentials
        self.session = session
        self.endpoint = endpoint
        self.resetCreditsEndpoint = resetCreditsEndpoint
            ?? endpoint.deletingLastPathComponent().appendingPathComponent("rate-limit-reset-credits")
    }

    func fetch() async throws -> UsageSnapshot {
        let data = try await fetchData(from: endpoint)
        let snapshot: UsageSnapshot
        do {
            snapshot = try JSONDecoder().decode(UsageResponseDTO.self, from: data).snapshot()
        } catch {
            throw CodexUsageError.decodingFailed
        }

        // Expiry metadata is currently available only from a separate read-only
        // endpoint. Treat it as optional so quota and count display survive an
        // endpoint change, entitlement difference, or transient failure.
        guard let count = snapshot.availableResetCredits,
              count > 0,
              let details = try? await fetchResetCreditDetails() else {
            return snapshot
        }
        return snapshot.adding(resetCreditDetails: details)
    }

    private func fetchResetCreditDetails() async throws -> ResetCreditDetails {
        let data = try await fetchData(from: resetCreditsEndpoint, timeoutInterval: 5)
        do {
            return try JSONDecoder().decode(ResetCreditDetailsDTO.self, from: data).details()
        } catch {
            throw CodexUsageError.decodingFailed
        }
    }

    private func fetchData(
        from endpoint: URL,
        timeoutInterval: TimeInterval = 15
    ) async throws -> Data {
        guard endpoint.scheme == "https",
              endpoint.host == self.endpoint.host,
              endpoint.port == self.endpoint.port else {
            throw CodexUsageError.invalidHTTPResponse
        }
        var request = URLRequest(
            url: endpoint,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: timeoutInterval
        )
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        if let accountID = credentials.accountID, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CodexUsageError.invalidHTTPResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw CodexUsageError.reauthenticationRequired
            }
            throw CodexUsageError.httpStatus(httpResponse.statusCode)
        }

        return data
    }
}
