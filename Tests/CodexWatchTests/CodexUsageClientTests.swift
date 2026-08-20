import Foundation
import XCTest
@testable import CodexWatch

final class CodexUsageClientTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testWeeklyOnlyResponseCreatesOneWeeklyWindow() async throws {
        let responseData = try Data(contentsOf: fixtureURL("usage-weekly-only.json"))
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-access-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "ChatGPT-Account-Id"), "acct_fixture")
            return (self.response(status: 200), responseData)
        }

        let snapshot = try await makeClient().fetch()

        XCTAssertEqual(snapshot.windows.count, 1)
        XCTAssertEqual(snapshot.plan, .plus)
        XCTAssertEqual(snapshot.creditsRemaining, .balance("100"))
        XCTAssertEqual(snapshot.windows.first?.kind, .weekly)
        XCTAssertEqual(snapshot.windows.first?.usedPercent, 5)
        XCTAssertEqual(snapshot.windows.first?.durationSeconds, 604_800)
        XCTAssertEqual(snapshot.availableResetCredits, 2)
    }

    func testAnalyticsResponseAggregatesCompleteNonnegativeDailyTotals() throws {
        let responseData = try Data(contentsOf: fixtureURL("usage-analytics-30-day.json"))
        let calendar = utcCalendar()
        let periodStart = calendar.date(from: DateComponents(year: 2026, month: 7, day: 22))!
        let periodEnd = calendar.date(from: DateComponents(year: 2026, month: 8, day: 20))!
        let fetchedAt = Date(timeIntervalSince1970: 1_779_153_600)

        let summary = try XCTUnwrap(
            JSONDecoder().decode(UsageAnalyticsResponseDTO.self, from: responseData).summary(
                periodStart: periodStart,
                periodEnd: periodEnd,
                calendar: calendar,
                fetchedAt: fetchedAt
            )
        )

        XCTAssertEqual(summary.periodStart, periodStart)
        XCTAssertEqual(summary.periodEnd, periodEnd)
        XCTAssertEqual(summary.totalTokens, 14_000)
        XCTAssertEqual(summary.uncachedInputTokens, 2_500)
        XCTAssertEqual(summary.cachedInputTokens, 4_500)
        XCTAssertEqual(summary.outputTokens, 7_000)
        XCTAssertEqual(summary.turns, 22)
        XCTAssertEqual(summary.chats, 5)
        XCTAssertEqual(summary.fetchedAt, fetchedAt)
    }

    func testAnalyticsResponseRejectsWrongGroupingOutOfRangeDuplicateOrMalformedDates() throws {
        let calendar = utcCalendar()
        let periodStart = calendar.date(from: DateComponents(year: 2026, month: 7, day: 22))!
        let periodEnd = calendar.date(from: DateComponents(year: 2026, month: 8, day: 20))!
        let totals = #"{"threads":1,"turns":2,"uncached_text_input_tokens":3,"cached_text_input_tokens":4,"text_output_tokens":5,"text_total_tokens":12}"#
        let invalidResponses = [
            #"{"group_by":"week","data":[{"date":"2026-08-20","totals":\#(totals)}]}"#,
            #"{"group_by":"day","data":[{"date":"2026-07-21","totals":\#(totals)}]}"#,
            #"{"group_by":"day","data":[{"date":"2026-08-20","totals":\#(totals)},{"date":"2026-08-20","totals":\#(totals)}]}"#,
            #"{"group_by":"day","data":[{"date":"2026-8-20","totals":\#(totals)}]}"#
        ]

        for json in invalidResponses {
            let response = try JSONDecoder().decode(
                UsageAnalyticsResponseDTO.self,
                from: Data(json.utf8)
            )

            XCTAssertNil(
                response.summary(
                    periodStart: periodStart,
                    periodEnd: periodEnd,
                    calendar: calendar
                )
            )
        }
    }

    func testAnalyticsResponseRejectsAggregateOverflow() throws {
        let calendar = utcCalendar()
        let response = try JSONDecoder().decode(
            UsageAnalyticsResponseDTO.self,
            from: Data(
                #"{"group_by":"day","data":[{"date":"2026-08-19","totals":{"threads":1,"turns":1,"uncached_text_input_tokens":1,"cached_text_input_tokens":1,"text_output_tokens":1,"text_total_tokens":9223372036854775807}},{"date":"2026-08-20","totals":{"threads":1,"turns":1,"uncached_text_input_tokens":1,"cached_text_input_tokens":1,"text_output_tokens":1,"text_total_tokens":1}}]}"#.utf8
            )
        )

        XCTAssertNil(
            response.summary(
                periodStart: calendar.date(from: DateComponents(year: 2026, month: 7, day: 22))!,
                periodEnd: calendar.date(from: DateComponents(year: 2026, month: 8, day: 20))!,
                calendar: calendar
            )
        )
    }

    func testAnalyticsResponseRejectsNegativeOrIncompleteDailyTotals() throws {
        for json in [
            #"{"data":[{"date":"2026-08-20","totals":{"threads":1,"turns":2,"uncached_text_input_tokens":3,"cached_text_input_tokens":4,"text_output_tokens":5,"text_total_tokens":-1}}]}"#,
            #"{"data":[{"date":"2026-08-20","totals":{"threads":1,"turns":2,"cached_text_input_tokens":4,"text_output_tokens":5,"text_total_tokens":9}}]}"#,
            #"{"data":[]}"#
        ] {
            let response = try JSONDecoder().decode(
                UsageAnalyticsResponseDTO.self,
                from: Data(json.utf8)
            )

            XCTAssertNil(
                response.summary(
                    periodStart: Date(timeIntervalSince1970: 1_776_643_200),
                    periodEnd: Date(timeIntervalSince1970: 1_779_148_800),
                    fetchedAt: Date(timeIntervalSince1970: 1_779_153_600)
                )
            )
        }
    }

    func testAnalyticsRequestUsesTrailingThirtyDaysAndExistingCredentialBoundary() async throws {
        let responseData = try Data(contentsOf: fixtureURL("usage-analytics-30-day.json"))
        let referenceDate = ISO8601DateFormatter().date(from: "2026-08-20T12:00:00Z")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(
                request.url?.path,
                "/backend-api/wham/analytics/daily-workspace-usage-counts"
            )
            let query = Dictionary(
                uniqueKeysWithValues: URLComponents(
                    url: try XCTUnwrap(request.url),
                    resolvingAgainstBaseURL: false
                )?.queryItems?.compactMap { item in
                    item.value.map { (item.name, $0) }
                } ?? []
            )
            XCTAssertEqual(query["start_date"], "2026-07-22")
            XCTAssertEqual(query["end_date"], "2026-08-20")
            XCTAssertEqual(query["group_by"], "day")
            XCTAssertEqual(query["workspace_user"], "true")
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-access-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "ChatGPT-Account-Id"), "acct_fixture")
            return (self.response(status: 200, url: request.url), responseData)
        }

        let summary = try await makeClient().fetchAnalytics(
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(summary.totalTokens, 14_000)
        XCTAssertEqual(summary.periodStart, calendar.startOfDay(for: referenceDate).addingTimeInterval(-29 * 86_400))
        XCTAssertEqual(summary.periodEnd, calendar.startOfDay(for: referenceDate))
    }

    func testAnalyticsDatasetRequestUsesTrailingThreeHundredSixtyFiveDays() async throws {
        let responseData = try Data(contentsOf: fixtureURL("usage-analytics-365-partial.json"))
        let referenceDate = ISO8601DateFormatter().date(from: "2026-08-20T12:00:00Z")!
        let calendar = utcCalendar()
        MockURLProtocol.requestHandler = { request in
            let query = Dictionary(
                uniqueKeysWithValues: URLComponents(
                    url: try XCTUnwrap(request.url),
                    resolvingAgainstBaseURL: false
                )?.queryItems?.compactMap { item in
                    item.value.map { (item.name, $0) }
                } ?? []
            )
            XCTAssertEqual(query["start_date"], "2025-08-21")
            XCTAssertEqual(query["end_date"], "2026-08-20")
            XCTAssertEqual(query["group_by"], "day")
            XCTAssertEqual(query["workspace_user"], "true")
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-access-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "ChatGPT-Account-Id"), "acct_fixture")
            return (self.response(status: 200, url: request.url), responseData)
        }

        let dataset = try await makeClient().fetchAnalyticsDataset(
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(dataset.requestedStart, day("2025-08-21", calendar: calendar))
        XCTAssertEqual(dataset.requestedEnd, day("2026-08-20", calendar: calendar))
        XCTAssertEqual(dataset.days.count, 2)
    }

    func testAnalyticsEndpointOnAnotherHostIsRejectedBeforeSendingCredentials() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        MockURLProtocol.requestHandler = { _ in
            XCTFail("An analytics request to another host must not be sent")
            return (self.response(status: 500), Data())
        }
        let client = CodexUsageClient(
            credentials: CodexCredentials(accessToken: "fixture-access-token", accountID: nil),
            session: URLSession(configuration: configuration),
            endpoint: URL(string: "https://example.test/backend-api/wham/usage")!,
            analyticsEndpoint: URL(string: "https://other.example/analytics")!
        )

        do {
            _ = try await client.fetchAnalytics()
            XCTFail("Expected an invalid response error")
        } catch let error as CodexUsageError {
            XCTAssertEqual(error, .invalidHTTPResponse)
        }
    }

    func testOversizedAnalyticsResponseIsRejectedBeforeDecoding() async throws {
        let oversizedResponse = Data(repeating: 0x20, count: 1_048_577)
        MockURLProtocol.requestHandler = { request in
            (self.response(status: 200, url: request.url), oversizedResponse)
        }

        do {
            _ = try await makeClient().fetchAnalytics()
            XCTFail("Expected an oversized response error")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .dataLengthExceedsMaximum)
        }
    }

    func testMissingNewAnalyticsPreservesLastSuccessfulInMemorySummary() {
        let previous = UsageAnalyticsSummary(
            periodStart: Date(timeIntervalSince1970: 1_776_643_200),
            periodEnd: Date(timeIntervalSince1970: 1_779_148_800),
            totalTokens: 14_000,
            uncachedInputTokens: 2_500,
            cachedInputTokens: 4_500,
            outputTokens: 7_000,
            turns: 22,
            chats: 5,
            fetchedAt: Date(timeIntervalSince1970: 1_779_153_600)
        )
        let snapshot = UsageSnapshot(windows: [], analytics: previous)

        XCTAssertEqual(snapshot.adding(analytics: nil).analytics, previous)
    }

    func testMultipleWindowsAreClassifiedIndependently() async throws {
        let responseData = try Data(contentsOf: fixtureURL("usage-multiple-windows.json"))
        MockURLProtocol.requestHandler = { _ in
            (self.response(status: 200), responseData)
        }

        let snapshot = try await makeClient().fetch()

        XCTAssertEqual(snapshot.windows.map(\.kind), [.rolling(hours: 5), .weekly])
        XCTAssertEqual(snapshot.plan, .plus)
        XCTAssertEqual(snapshot.windows.map(\.id), ["primary", "secondary"])
        XCTAssertEqual(snapshot.availableResetCredits, 1)
    }

    func testCurrentResponseReadsWindowsNestedUnderRateLimit() async throws {
        let responseData = try Data(contentsOf: fixtureURL("usage-nested-rate-limit.json"))
        MockURLProtocol.requestHandler = { _ in
            (self.response(status: 200), responseData)
        }

        let snapshot = try await makeClient().fetch()

        XCTAssertEqual(snapshot.windows.count, 1)
        XCTAssertEqual(snapshot.plan, .plus)
        XCTAssertEqual(snapshot.windows.first?.kind, .weekly)
        XCTAssertEqual(snapshot.windows.first?.usedPercent, 20)
        XCTAssertEqual(snapshot.windows.first?.remainingPercent, 80)
    }

    func testUnknownOrMissingPlanIsNotExposed() throws {
        let unknown = try JSONDecoder().decode(
            UsageResponseDTO.self,
            from: Data(#"{"plan_type":"unreleased-tier"}"#.utf8)
        ).snapshot()
        let missing = try JSONDecoder().decode(
            UsageResponseDTO.self,
            from: Data("{}".utf8)
        ).snapshot()

        XCTAssertNil(unknown.plan)
        XCTAssertNil(missing.plan)
    }

    func testProLitePlanIsRecognized() throws {
        let snapshot = try JSONDecoder().decode(
            UsageResponseDTO.self,
            from: Data(#"{"plan_type":"prolite"}"#.utf8)
        ).snapshot()

        XCTAssertEqual(snapshot.plan, .proLite)
    }

    func testMissingEntitlementOrInvalidCreditsBalanceIsNotFabricated() throws {
        for json in [
            #"{}"#,
            #"{"credits":{}}"#,
            #"{"credits":{"has_credits":"yes","unlimited":false,"balance":"10"}}"#,
            #"{"credits":{"has_credits":false,"unlimited":false,"balance":"10"}}"#,
            #"{"credits":{"has_credits":true,"unlimited":false,"balance":""}}"#,
            #"{"credits":{"has_credits":true,"unlimited":false,"balance":"NaN"}}"#,
            #"{"credits":{"has_credits":true,"unlimited":false,"balance":"not-a-number"}}"#
        ] {
            let snapshot = try JSONDecoder().decode(
                UsageResponseDTO.self,
                from: Data(json.utf8)
            ).snapshot()
            XCTAssertNil(snapshot.creditsRemaining)
        }
    }

    func testNumericAndNegativeCreditsBalancesAreAccepted() throws {
        let positive = try JSONDecoder().decode(
            UsageResponseDTO.self,
            from: Data(#"{"credits":{"has_credits":true,"unlimited":false,"balance":2.5}}"#.utf8)
        ).snapshot()
        let negative = try JSONDecoder().decode(
            UsageResponseDTO.self,
            from: Data(#"{"credits":{"has_credits":true,"unlimited":false,"balance":"-1.25"}}"#.utf8)
        ).snapshot()

        XCTAssertEqual(positive.creditsRemaining, .balance("2.5"))
        XCTAssertEqual(negative.creditsRemaining, .balance("-1.25"))
    }

    func testUnlimitedCreditsTakePrecedenceOverBalance() throws {
        let snapshot = try JSONDecoder().decode(
            UsageResponseDTO.self,
            from: Data(#"{"credits":{"has_credits":true,"unlimited":true,"balance":"10"}}"#.utf8)
        ).snapshot()

        XCTAssertEqual(snapshot.creditsRemaining, .unlimited)
    }

    func testResetCreditDetailsAddNextSupportedAvailableExpiry() async throws {
        let usageData = try Data(contentsOf: fixtureURL("usage-weekly-only.json"))
        let detailsData = try Data(contentsOf: fixtureURL("reset-credits-details.json"))
        MockURLProtocol.requestHandler = { request in
            if request.url?.path == CodexUsageClient.resetCreditsPath {
                XCTAssertNil(request.value(forHTTPHeaderField: "OpenAI-Beta"))
                XCTAssertNil(request.value(forHTTPHeaderField: "originator"))
                return (self.response(status: 200, url: request.url), detailsData)
            }
            return (self.response(status: 200, url: request.url), usageData)
        }

        let snapshot = try await makeClient().fetch()

        XCTAssertEqual(snapshot.availableResetCredits, 2)
        XCTAssertEqual(snapshot.resetCredits.count, 4)
        XCTAssertEqual(snapshot.resetCredits.filter { $0.status == "available" }.count, 3)
        XCTAssertEqual(
            snapshot.nextResetCreditGrantedAt,
            ISO8601DateFormatter().date(from: "2029-12-03T08:30:45Z")
        )
        XCTAssertEqual(
            snapshot.nextResetCreditExpiry,
            ISO8601DateFormatter().date(from: "2030-01-02T08:30:45Z")
        )
    }

    func testResetCreditDetailFailurePreservesUsageAndCount() async throws {
        let usageData = try Data(contentsOf: fixtureURL("usage-weekly-only.json"))
        MockURLProtocol.requestHandler = { request in
            if request.url?.path == CodexUsageClient.resetCreditsPath {
                return (self.response(status: 503, url: request.url), Data())
            }
            return (self.response(status: 200, url: request.url), usageData)
        }

        let snapshot = try await makeClient().fetch()

        XCTAssertEqual(snapshot.availableResetCredits, 2)
        XCTAssertNil(snapshot.nextResetCreditGrantedAt)
        XCTAssertNil(snapshot.nextResetCreditExpiry)
        XCTAssertEqual(snapshot.windows.count, 1)
    }

    func testZeroResetCreditsDoesNotRequestDetails() async throws {
        let responseData = Data(
            """
            {
              "secondary_window": {
                "used_percent": 5,
                "limit_window_seconds": 604800
              },
              "rate_limit_reset_credits": {
                "available_count": 0
              }
            }
            """.utf8
        )
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/backend-api/wham/usage")
            return (self.response(status: 200, url: request.url), responseData)
        }

        let snapshot = try await makeClient().fetch()

        XCTAssertEqual(snapshot.availableResetCredits, 0)
        XCTAssertNil(snapshot.nextResetCreditGrantedAt)
        XCTAssertNil(snapshot.nextResetCreditExpiry)
    }

    func testRequestDisablesCaching() async throws {
        let responseData = try Data(contentsOf: fixtureURL("usage-weekly-only.json"))
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            return (self.response(status: 200), responseData)
        }

        _ = try await makeClient().fetch()
    }

    func testOversizedUsageResponseIsRejectedBeforeDecoding() async throws {
        let oversizedResponse = Data(repeating: 0x20, count: 1_048_577)
        MockURLProtocol.requestHandler = { request in
            (self.response(status: 200, url: request.url), oversizedResponse)
        }

        do {
            _ = try await makeClient().fetch()
            XCTFail("Expected an oversized response error")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .dataLengthExceedsMaximum)
        } catch {
            XCTFail("Expected an oversized response error, got \(error)")
        }
    }

    func testExtremeResetTimestampIsDiscarded() throws {
        let snapshot = try JSONDecoder().decode(
            UsageResponseDTO.self,
            from: Data(
                #"{"secondary_window":{"used_percent":5,"limit_window_seconds":604800,"reset_at":1e300}}"#.utf8
            )
        ).snapshot()

        XCTAssertNil(snapshot.weeklyWindow?.resetAt)
    }

    func testUnauthorizedResponseRequiresReauthentication() async throws {
        MockURLProtocol.requestHandler = { _ in
            (self.response(status: 401), Data())
        }

        do {
            _ = try await makeClient().fetch()
            XCTFail("Expected a reauthentication error")
        } catch let error as CodexUsageError {
            XCTAssertEqual(error, .reauthenticationRequired)
        }
    }

    func testPlainHTTPIsRejectedBeforeSendingCredentials() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        MockURLProtocol.requestHandler = { _ in
            XCTFail("An insecure request must not be sent")
            return (self.response(status: 500), Data())
        }
        let client = CodexUsageClient(
            credentials: CodexCredentials(accessToken: "fixture-access-token", accountID: nil),
            session: URLSession(configuration: configuration),
            endpoint: URL(string: "http://example.test/backend-api/wham/usage")!
        )

        do {
            _ = try await client.fetch()
            XCTFail("Expected an invalid response error")
        } catch let error as CodexUsageError {
            XCTAssertEqual(error, .invalidHTTPResponse)
        }
    }

    func testResetCreditEndpointOnAnotherHostIsRejectedWithoutBreakingUsage() async throws {
        let usageData = try Data(contentsOf: fixtureURL("usage-weekly-only.json"))
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.host, "example.test")
            return (self.response(status: 200, url: request.url), usageData)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let client = CodexUsageClient(
            credentials: CodexCredentials(accessToken: "fixture-access-token", accountID: nil),
            session: URLSession(configuration: configuration),
            endpoint: URL(string: "https://example.test/backend-api/wham/usage")!,
            resetCreditsEndpoint: URL(string: "https://other.example/reset-credits")!
        )

        let snapshot = try await client.fetch()

        XCTAssertEqual(snapshot.availableResetCredits, 2)
        XCTAssertNil(snapshot.nextResetCreditExpiry)
    }

    private func makeClient() -> CodexUsageClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return CodexUsageClient(
            credentials: CodexCredentials(
                accessToken: "fixture-access-token",
                accountID: "acct_fixture"
            ),
            session: URLSession(configuration: configuration),
            endpoint: URL(string: "https://example.test/backend-api/wham/usage")!
        )
    }

    private func response(status: Int, url: URL? = nil) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url ?? URL(string: "https://example.test/backend-api/wham/usage")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func day(_ text: String, calendar: Calendar) -> Date {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        return calendar.date(from: DateComponents(
            year: parts[0],
            month: parts[1],
            day: parts[2]
        ))!
    }

    private func fixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(name)
    }
}

private final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let handler = Self.requestHandler else {
                throw URLError(.badServerResponse)
            }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
