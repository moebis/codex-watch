import Foundation

struct UsageResponseDTO: Decodable {
    let planType: String?
    let primaryWindow: WindowDTO?
    let secondaryWindow: WindowDTO?
    let rateLimit: RateLimitDTO?
    let rateLimitResetCredits: ResetCreditsDTO?
    let credits: CreditsDTO?

    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
        case rateLimit = "rate_limit"
        case rateLimitResetCredits = "rate_limit_reset_credits"
        case credits
    }

    func snapshot(fetchedAt: Date = .now) -> UsageSnapshot {
        // The current ChatGPT endpoint nests the windows under `rate_limit`.
        // Keep the top-level fields as a compatibility fallback because older
        // responses (and our fixtures) exposed them directly.
        let windows = [
            makeWindow(id: "primary", dto: primaryWindow ?? rateLimit?.primaryWindow),
            makeWindow(id: "secondary", dto: secondaryWindow ?? rateLimit?.secondaryWindow)
        ].compactMap { $0 }

        return UsageSnapshot(
            plan: planType.flatMap(ChatGPTPlan.init(apiValue:)),
            creditsRemaining: credits?.validatedRemaining,
            windows: windows,
            availableResetCredits: availableResetCredits,
            fetchedAt: fetchedAt
        )
    }

    private var availableResetCredits: Int? {
        guard let count = rateLimitResetCredits?.availableCount, count >= 0 else { return nil }
        return count
    }

    private func makeWindow(id: String, dto: WindowDTO?) -> UsageWindow? {
        guard let dto,
              let usedPercent = dto.usedPercent,
              let seconds = dto.limitWindowSeconds else {
            return nil
        }

        return UsageWindow(
            id: id,
            kind: UsageWindowClassifier.kind(seconds: seconds),
            usedPercent: usedPercent,
            resetAt: dto.resetAt,
            durationSeconds: TimeInterval(seconds)
        )
    }
}

struct CreditsDTO: Decodable {
    let hasCredits: Bool?
    let unlimited: Bool?
    let balance: String?

    enum CodingKeys: String, CodingKey {
        case hasCredits = "has_credits"
        case unlimited
        case balance
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hasCredits = try? container.decodeIfPresent(Bool.self, forKey: .hasCredits)
        unlimited = try? container.decodeIfPresent(Bool.self, forKey: .unlimited)
        if let text = try? container.decodeIfPresent(String.self, forKey: .balance) {
            balance = text
        } else if let number = try? container.decodeIfPresent(Decimal.self, forKey: .balance) {
            balance = NSDecimalNumber(decimal: number).stringValue
        } else {
            balance = nil
        }
    }

    var validatedRemaining: CreditsRemaining? {
        if unlimited == true { return .unlimited }
        guard hasCredits == true, let balance else { return nil }
        let trimmed = balance.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.count <= 64,
              let value = Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX")),
              !value.isNaN else { return nil }
        return .balance(trimmed)
    }
}

struct ResetCreditsDTO: Decodable {
    let availableCount: Int?

    enum CodingKeys: String, CodingKey {
        case availableCount = "available_count"
    }
}

struct ResetCreditDetailsDTO: Decodable {
    let credits: [ResetCreditDTO]?

    func details() -> ResetCreditDetails {
        let nextCredit = (credits ?? [])
            .filter { $0.status == "available" && $0.isSupportedByPlan != false }
            .filter { $0.expiresAt != nil }
            .min { lhs, rhs in
                lhs.expiresAt ?? .distantFuture < rhs.expiresAt ?? .distantFuture
            }
        return ResetCreditDetails(
            nextGrantedAt: nextCredit?.grantedAt,
            nextExpiry: nextCredit?.expiresAt
        )
    }
}

struct ResetCreditDTO: Decodable {
    let status: String?
    let grantedAt: Date?
    let expiresAt: Date?
    let isSupportedByPlan: Bool?

    enum CodingKeys: String, CodingKey {
        case status
        case grantedAt = "granted_at"
        case expiresAt = "expires_at"
        case isSupportedByPlan = "is_supported_by_plan"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        isSupportedByPlan = try container.decodeIfPresent(Bool.self, forKey: .isSupportedByPlan)
        grantedAt = container.decodeISO8601DateIfPresent(forKey: .grantedAt)
        expiresAt = container.decodeISO8601DateIfPresent(forKey: .expiresAt)
    }
}

struct RateLimitDTO: Decodable {
    let primaryWindow: WindowDTO?
    let secondaryWindow: WindowDTO?

    enum CodingKeys: String, CodingKey {
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }
}

struct WindowDTO: Decodable {
    let usedPercent: Double?
    let limitWindowSeconds: Int?
    let resetAt: Date?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case limitWindowSeconds = "limit_window_seconds"
        case resetAt = "reset_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        usedPercent = try container.decodeIfPresent(Double.self, forKey: .usedPercent)
        limitWindowSeconds = try container.decodeIfPresent(Int.self, forKey: .limitWindowSeconds)

        if let epoch = try? container.decode(Double.self, forKey: .resetAt) {
            let seconds = epoch > 1_000_000_000_000 ? epoch / 1_000 : epoch
            if seconds.isFinite,
               (0 ... Date.distantFuture.timeIntervalSince1970).contains(seconds) {
                resetAt = Date(timeIntervalSince1970: seconds)
            } else {
                resetAt = nil
            }
        } else if let text = try? container.decode(String.self, forKey: .resetAt) {
            resetAt = Self.parseISO8601Date(text)
        } else {
            resetAt = nil
        }
    }

    private static func parseISO8601Date(_ text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}

private extension KeyedDecodingContainer {
    func decodeISO8601DateIfPresent(forKey key: Key) -> Date? {
        guard let text = try? decodeIfPresent(String.self, forKey: key) else {
            return nil
        }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}
