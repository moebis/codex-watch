import Foundation

protocol LegacyUsageServing: Sendable {
    func fetch() async throws -> UsageSnapshot
    func fetchProfileStats(referenceDate: Date) async throws -> CodexProfileStats
    func fetchAnalyticsDataset(
        referenceDate: Date,
        calendar: Calendar
    ) async throws -> UsageAnalyticsDataset
}

extension CodexUsageClient: LegacyUsageServing {}

enum CodexDataSourceStrategy {
    static func fetchQuota(
        account: (any CodexAccountServing)?,
        legacy: (any LegacyUsageServing)?,
        fetchedAt: Date
    ) async -> QuotaRefreshAttempt {
        var officialError: CodexAccountServiceError?
        if let account {
            do {
                return .success(try await account.fetchQuota(fetchedAt: fetchedAt))
            } catch let error as CodexAccountServiceError {
                officialError = error
            } catch {
                officialError = .unavailable
            }
        }

        if let legacy {
            do {
                return .success(try await legacy.fetch())
            } catch CodexUsageError.reauthenticationRequired {
                return .failure(.signInRequired)
            } catch {
                return .failure(officialError == .signInRequired ? .signInRequired : .quotaUnavailable)
            }
        }

        return .failure(officialError == .signInRequired ? .signInRequired : .quotaUnavailable)
    }

    static func fetchProfile(
        account: (any CodexAccountServing)?,
        legacy: (any LegacyUsageServing)?,
        fetchedAt: Date
    ) async -> CapabilityRefreshAttempt<CodexProfileStats> {
        if let legacy,
           let profile = try? await legacy.fetchProfileStats(referenceDate: fetchedAt) {
            return .success(profile)
        }
        if let account,
           let profile = try? await account.fetchProfile(fetchedAt: fetchedAt) {
            return .success(profile)
        }
        return .failure
    }

    static func fetchAnalytics(
        legacy: (any LegacyUsageServing)?,
        referenceDate: Date,
        calendar: Calendar = .current
    ) async -> CapabilityRefreshAttempt<UsageAnalyticsDataset> {
        guard let legacy else { return .failure }
        do {
            return .success(try await legacy.fetchAnalyticsDataset(
                referenceDate: referenceDate,
                calendar: calendar
            ))
        } catch {
            return .failure
        }
    }
}
