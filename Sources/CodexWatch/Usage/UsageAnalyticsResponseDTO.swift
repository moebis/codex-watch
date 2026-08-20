import Foundation

struct UsageAnalyticsResponseDTO: Decodable {
    let data: [UsageAnalyticsDayDTO]
    let groupBy: String?

    enum CodingKeys: String, CodingKey {
        case data
        case groupBy = "group_by"
    }

    func summary(
        periodStart: Date,
        periodEnd: Date,
        calendar: Calendar = .current,
        fetchedAt: Date = .now
    ) -> UsageAnalyticsSummary? {
        let requestedStart = calendar.startOfDay(for: periodStart)
        let requestedEnd = calendar.startOfDay(for: periodEnd)
        guard groupBy == "day",
              !data.isEmpty,
              requestedStart <= requestedEnd else { return nil }

        var aggregate = UsageAnalyticsTotalsDTO.zero
        var observedDates = Set<Date>()
        for day in data {
            guard let dateText = day.date,
                  let date = Self.parseDate(dateText, calendar: calendar),
                  date >= requestedStart,
                  date <= requestedEnd,
                  observedDates.insert(date).inserted,
                  let totals = day.totals,
                  totals.isCompleteAndNonnegative,
                  let next = aggregate.adding(totals) else { return nil }
            aggregate = next
        }

        guard let totalTokens = aggregate.textTotalTokens,
              let uncachedInputTokens = aggregate.uncachedTextInputTokens,
              let cachedInputTokens = aggregate.cachedTextInputTokens,
              let outputTokens = aggregate.textOutputTokens,
              let turns = aggregate.turns,
              let chats = aggregate.threads else { return nil }

        return UsageAnalyticsSummary(
            periodStart: periodStart,
            periodEnd: periodEnd,
            totalTokens: totalTokens,
            uncachedInputTokens: uncachedInputTokens,
            cachedInputTokens: cachedInputTokens,
            outputTokens: outputTokens,
            turns: turns,
            chats: chats,
            fetchedAt: fetchedAt
        )
    }

    private static func parseDate(_ text: String, calendar: Calendar) -> Date? {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4,
              parts[1].count == 2,
              parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy(\.isNumber) }),
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else { return nil }

        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        guard let value = calendar.date(from: components) else { return nil }

        let roundTrip = calendar.dateComponents([.year, .month, .day], from: value)
        guard roundTrip.year == year,
              roundTrip.month == month,
              roundTrip.day == day else { return nil }
        return calendar.startOfDay(for: value)
    }
}

struct UsageAnalyticsDayDTO: Decodable {
    let date: String?
    let totals: UsageAnalyticsTotalsDTO?
}

struct UsageAnalyticsTotalsDTO: Decodable {
    let threads: Int64?
    let turns: Int64?
    let uncachedTextInputTokens: Int64?
    let cachedTextInputTokens: Int64?
    let textOutputTokens: Int64?
    let textTotalTokens: Int64?

    enum CodingKeys: String, CodingKey {
        case threads
        case turns
        case uncachedTextInputTokens = "uncached_text_input_tokens"
        case cachedTextInputTokens = "cached_text_input_tokens"
        case textOutputTokens = "text_output_tokens"
        case textTotalTokens = "text_total_tokens"
    }

    static let zero = UsageAnalyticsTotalsDTO(
        threads: 0,
        turns: 0,
        uncachedTextInputTokens: 0,
        cachedTextInputTokens: 0,
        textOutputTokens: 0,
        textTotalTokens: 0
    )

    var isCompleteAndNonnegative: Bool {
        [
            threads,
            turns,
            uncachedTextInputTokens,
            cachedTextInputTokens,
            textOutputTokens,
            textTotalTokens
        ].allSatisfy { value in
            guard let value else { return false }
            return value >= 0
        }
    }

    func adding(_ other: UsageAnalyticsTotalsDTO) -> UsageAnalyticsTotalsDTO? {
        guard let threads = Self.sum(threads, other.threads),
              let turns = Self.sum(turns, other.turns),
              let uncached = Self.sum(uncachedTextInputTokens, other.uncachedTextInputTokens),
              let cached = Self.sum(cachedTextInputTokens, other.cachedTextInputTokens),
              let output = Self.sum(textOutputTokens, other.textOutputTokens),
              let total = Self.sum(textTotalTokens, other.textTotalTokens) else { return nil }
        return UsageAnalyticsTotalsDTO(
            threads: threads,
            turns: turns,
            uncachedTextInputTokens: uncached,
            cachedTextInputTokens: cached,
            textOutputTokens: output,
            textTotalTokens: total
        )
    }

    private static func sum(_ lhs: Int64?, _ rhs: Int64?) -> Int64? {
        guard let lhs, let rhs else { return nil }
        let result = lhs.addingReportingOverflow(rhs)
        return result.overflow ? nil : result.partialValue
    }
}
