import Foundation

struct UsageAnalyticsResponseDTO: Decodable {
    let data: [UsageAnalyticsDayDTO]
    let groupBy: String?

    enum CodingKeys: String, CodingKey {
        case data
        case groupBy = "group_by"
    }

    func dataset(
        requestedStart: Date,
        requestedEnd: Date,
        calendar: Calendar = .current,
        fetchedAt: Date = .now
    ) -> UsageAnalyticsDataset? {
        let normalizedStart = calendar.startOfDay(for: requestedStart)
        let normalizedEnd = calendar.startOfDay(for: requestedEnd)
        guard groupBy == "day", normalizedStart <= normalizedEnd else { return nil }

        var observedDates = Set<Date>()
        var validatedDays: [UsageAnalyticsDay] = []
        var modelBreakdownIsPartial = false
        var clientBreakdownIsPartial = false

        for day in data {
            guard let dateText = day.date,
                  let date = Self.parseDate(dateText, calendar: calendar),
                  (normalizedStart ... normalizedEnd).contains(date),
                  observedDates.insert(date).inserted,
                  let totals = day.totals?.validatedTotals else { return nil }

            var models: [UsageModelActivity] = []
            if day.modelBreakdownDecodeFailed { modelBreakdownIsPartial = true }
            for lossy in day.models ?? [] {
                guard let activity = lossy.value?.validatedActivity else {
                    modelBreakdownIsPartial = true
                    continue
                }
                models.append(activity)
            }

            var clients: [UsageClientActivity] = []
            if day.clientBreakdownDecodeFailed { clientBreakdownIsPartial = true }
            for lossy in day.clients ?? [] {
                guard let activity = lossy.value?.validatedActivity else {
                    clientBreakdownIsPartial = true
                    continue
                }
                clients.append(activity)
            }

            validatedDays.append(UsageAnalyticsDay(
                date: date,
                totals: totals,
                models: models,
                clients: clients
            ))
        }

        return UsageAnalyticsDataset(
            requestedStart: normalizedStart,
            requestedEnd: normalizedEnd,
            days: validatedDays.sorted { $0.date < $1.date },
            fetchedAt: fetchedAt,
            modelBreakdownIsPartial: modelBreakdownIsPartial,
            clientBreakdownIsPartial: clientBreakdownIsPartial
        )
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
    let models: [LossyUsageModelDTO]?
    let clients: [LossyUsageClientDTO]?
    let modelBreakdownDecodeFailed: Bool
    let clientBreakdownDecodeFailed: Bool

    enum CodingKeys: String, CodingKey {
        case date
        case totals
        case models
        case clients
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try? container.decodeIfPresent(String.self, forKey: .date)
        totals = try? container.decodeIfPresent(UsageAnalyticsTotalsDTO.self, forKey: .totals)

        do {
            models = try container.decodeIfPresent([LossyUsageModelDTO].self, forKey: .models)
            modelBreakdownDecodeFailed = models == nil
        } catch {
            models = nil
            modelBreakdownDecodeFailed = true
        }

        do {
            clients = try container.decodeIfPresent([LossyUsageClientDTO].self, forKey: .clients)
            clientBreakdownDecodeFailed = clients == nil
        } catch {
            clients = nil
            clientBreakdownDecodeFailed = true
        }
    }
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

    var validatedTotals: UsageTokenTotals? {
        guard isCompleteAndNonnegative,
              let totalTokens = textTotalTokens,
              let uncachedInputTokens = uncachedTextInputTokens,
              let cachedInputTokens = cachedTextInputTokens,
              let outputTokens = textOutputTokens,
              let turns,
              let chats = threads else { return nil }
        return UsageTokenTotals(
            totalTokens: totalTokens,
            uncachedInputTokens: uncachedInputTokens,
            cachedInputTokens: cachedInputTokens,
            outputTokens: outputTokens,
            turns: turns,
            chats: chats
        )
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

struct UsageAnalyticsModelDTO: Decodable {
    let model: String?
    let threads: Int64?
    let turns: Int64?
    let credits: Decimal?

    enum CodingKeys: String, CodingKey {
        case model
        case threads
        case turns
        case credits
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        model = try? container.decodeIfPresent(String.self, forKey: .model)
        threads = try? container.decodeIfPresent(Int64.self, forKey: .threads)
        turns = try? container.decodeIfPresent(Int64.self, forKey: .turns)
        credits = Self.decodeDecimal(container, forKey: .credits)
    }

    var validatedActivity: UsageModelActivity? {
        guard let model = boundedAnalyticsIdentifier(model),
              let threads,
              threads >= 0,
              let turns,
              turns >= 0,
              let credits,
              !credits.isNaN,
              credits >= 0 else { return nil }
        return UsageModelActivity(
            model: model,
            turns: turns,
            chats: threads,
            credits: credits
        )
    }

    private static func decodeDecimal(
        _ container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> Decimal? {
        if let value = try? container.decodeIfPresent(Decimal.self, forKey: key) {
            return value
        }
        guard let value = try? container.decodeIfPresent(String.self, forKey: key) else {
            return nil
        }
        return Decimal(
            string: value.trimmingCharacters(in: .whitespacesAndNewlines),
            locale: Locale(identifier: "en_US_POSIX")
        )
    }
}

struct UsageAnalyticsClientDTO: Decodable {
    let clientID: String?
    let totals: UsageAnalyticsTotalsDTO

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case threads
        case turns
        case uncachedTextInputTokens = "uncached_text_input_tokens"
        case cachedTextInputTokens = "cached_text_input_tokens"
        case textOutputTokens = "text_output_tokens"
        case textTotalTokens = "text_total_tokens"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        clientID = try? container.decodeIfPresent(String.self, forKey: .clientID)
        totals = UsageAnalyticsTotalsDTO(
            threads: try? container.decodeIfPresent(Int64.self, forKey: .threads),
            turns: try? container.decodeIfPresent(Int64.self, forKey: .turns),
            uncachedTextInputTokens: try? container.decodeIfPresent(
                Int64.self,
                forKey: .uncachedTextInputTokens
            ),
            cachedTextInputTokens: try? container.decodeIfPresent(
                Int64.self,
                forKey: .cachedTextInputTokens
            ),
            textOutputTokens: try? container.decodeIfPresent(Int64.self, forKey: .textOutputTokens),
            textTotalTokens: try? container.decodeIfPresent(Int64.self, forKey: .textTotalTokens)
        )
    }

    var validatedActivity: UsageClientActivity? {
        guard let clientID = boundedAnalyticsIdentifier(clientID),
              let totals = totals.validatedTotals else { return nil }
        return UsageClientActivity(clientID: clientID, totals: totals)
    }
}

struct LossyUsageModelDTO: Decodable {
    let value: UsageAnalyticsModelDTO?

    init(from decoder: Decoder) throws {
        value = try? decoder.singleValueContainer().decode(UsageAnalyticsModelDTO.self)
    }
}

struct LossyUsageClientDTO: Decodable {
    let value: UsageAnalyticsClientDTO?

    init(from decoder: Decoder) throws {
        value = try? decoder.singleValueContainer().decode(UsageAnalyticsClientDTO.self)
    }
}

private func boundedAnalyticsIdentifier(_ value: String?) -> String? {
    guard let value else { return nil }
    var result = ""
    for character in value.trimmingCharacters(in: .whitespacesAndNewlines) {
        let candidate = result + String(character)
        guard candidate.utf8.count <= 128 else { break }
        result = candidate
    }
    return result.isEmpty ? nil : result
}
