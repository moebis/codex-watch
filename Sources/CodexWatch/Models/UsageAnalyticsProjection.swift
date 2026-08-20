import Foundation

enum AnalyticsRange: Int, CaseIterable, Identifiable, Sendable {
    case days7 = 7
    case days30 = 30
    case days90 = 90
    case days365 = 365

    var id: Int { rawValue }
    var title: String { "\(rawValue)d" }
}

enum UsageComparison: Equatable, Sendable {
    case percent(Double)
}

struct UsageDayCell: Equatable, Identifiable, Sendable {
    enum State: Equatable, Sendable {
        case observed(UsageTokenTotals)
        case missing
    }

    let date: Date
    let state: State

    var id: Date { date }
}

struct UsageModelRow: Equatable, Identifiable, Sendable {
    let model: String
    let turns: Int64
    let chats: Int64
    let credits: Decimal
    let turnShare: Double?

    var id: String { model }
}

struct UsageClientRow: Equatable, Identifiable, Sendable {
    let clientID: String
    let totals: UsageTokenTotals

    var id: String { clientID }
    var totalTokens: Int64 { totals.totalTokens }
    var uncachedInputTokens: Int64 { totals.uncachedInputTokens }
    var cachedInputTokens: Int64 { totals.cachedInputTokens }
    var outputTokens: Int64 { totals.outputTokens }
    var turns: Int64 { totals.turns }
    var chats: Int64 { totals.chats }
}

struct UsageAnalyticsProjection: Equatable, Sendable {
    let range: AnalyticsRange
    let periodStart: Date
    let periodEnd: Date
    let totals: UsageTokenTotals
    let days: [UsageDayCell]
    let models: [UsageModelRow]
    let clients: [UsageClientRow]
    let comparison: UsageComparison?
    let dataThrough: Date?
    let fetchedAt: Date
    let modelBreakdownIsPartial: Bool
    let clientBreakdownIsPartial: Bool

    var requestedDayCount: Int { range.rawValue }
    var observedDayCount: Int { days.count { cell in if case .observed = cell.state { true } else { false } } }
    var missingDayCount: Int { requestedDayCount - observedDayCount }
    var totalTokens: Int64 { totals.totalTokens }
    var uncachedInputTokens: Int64 { totals.uncachedInputTokens }
    var cachedInputTokens: Int64 { totals.cachedInputTokens }
    var outputTokens: Int64 { totals.outputTokens }
    var turns: Int64 { totals.turns }
    var chats: Int64 { totals.chats }

    static func make(
        dataset: UsageAnalyticsDataset,
        range: AnalyticsRange,
        referenceDate: Date = .now,
        calendar: Calendar = .current
    ) -> UsageAnalyticsProjection? {
        let requestedReference = calendar.startOfDay(for: referenceDate)
        let periodEnd = min(requestedReference, calendar.startOfDay(for: dataset.requestedEnd))
        guard let periodStart = calendar.date(
            byAdding: .day,
            value: -(range.rawValue - 1),
            to: periodEnd
        ),
        periodStart >= calendar.startOfDay(for: dataset.requestedStart) else { return nil }

        let currentDates = dateSequence(
            start: periodStart,
            count: range.rawValue,
            calendar: calendar
        )
        guard currentDates.count == range.rawValue else { return nil }
        let daysByDate = Dictionary(uniqueKeysWithValues: dataset.days.map { ($0.date, $0) })
        let observedDays = currentDates.compactMap { daysByDate[$0] }
        guard let totals = aggregateTotals(observedDays.map(\.totals)),
              let models = aggregateModels(observedDays, totalTurns: totals.turns),
              let clients = aggregateClients(observedDays) else { return nil }

        let cells = currentDates.map { date in
            UsageDayCell(
                date: date,
                state: daysByDate[date].map { .observed($0.totals) } ?? .missing
            )
        }

        return UsageAnalyticsProjection(
            range: range,
            periodStart: periodStart,
            periodEnd: periodEnd,
            totals: totals,
            days: cells,
            models: models,
            clients: clients,
            comparison: comparison(
                currentTotal: totals.totalTokens,
                currentObservedCount: observedDays.count,
                range: range,
                periodStart: periodStart,
                daysByDate: daysByDate,
                calendar: calendar
            ),
            dataThrough: observedDays.last?.date,
            fetchedAt: dataset.fetchedAt,
            modelBreakdownIsPartial: dataset.modelBreakdownIsPartial,
            clientBreakdownIsPartial: dataset.clientBreakdownIsPartial
        )
    }

    private static func comparison(
        currentTotal: Int64,
        currentObservedCount: Int,
        range: AnalyticsRange,
        periodStart: Date,
        daysByDate: [Date: UsageAnalyticsDay],
        calendar: Calendar
    ) -> UsageComparison? {
        guard range != .days365,
              currentObservedCount >= minimumComparisonCoverage(range.rawValue),
              let previousStart = calendar.date(
                  byAdding: .day,
                  value: -range.rawValue,
                  to: periodStart
              ) else { return nil }
        let previousDates = dateSequence(
            start: previousStart,
            count: range.rawValue,
            calendar: calendar
        )
        let previousDays = previousDates.compactMap { daysByDate[$0] }
        guard previousDays.count >= minimumComparisonCoverage(range.rawValue),
              let previousTotals = aggregateTotals(previousDays.map(\.totals)),
              previousTotals.totalTokens > 0 else { return nil }
        let change = Double(currentTotal - previousTotals.totalTokens)
            / Double(previousTotals.totalTokens)
        guard change.isFinite else { return nil }
        return .percent(change)
    }

    private static func minimumComparisonCoverage(_ dayCount: Int) -> Int {
        Int(ceil(Double(dayCount) * 0.9))
    }

    private static func dateSequence(
        start: Date,
        count: Int,
        calendar: Calendar
    ) -> [Date] {
        (0 ..< count).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: start).map(calendar.startOfDay(for:))
        }
    }

    private static func aggregateTotals(_ values: [UsageTokenTotals]) -> UsageTokenTotals? {
        values.reduce(UsageTokenTotals.zero) { partial, value in
            partial.flatMap { $0.adding(value) }
        }
    }

    private static func aggregateModels(
        _ days: [UsageAnalyticsDay],
        totalTurns: Int64
    ) -> [UsageModelRow]? {
        var aggregates: [String: ModelAggregate] = [:]
        for activity in days.flatMap(\.models) {
            let current = aggregates[activity.model] ?? .zero
            guard let next = current.adding(activity) else { return nil }
            aggregates[activity.model] = next
        }
        return aggregates.map { model, aggregate in
            UsageModelRow(
                model: model,
                turns: aggregate.turns,
                chats: aggregate.chats,
                credits: aggregate.credits,
                turnShare: totalTurns > 0 ? Double(aggregate.turns) / Double(totalTurns) : nil
            )
        }.sorted {
            $0.turns == $1.turns ? $0.model < $1.model : $0.turns > $1.turns
        }
    }

    private static func aggregateClients(_ days: [UsageAnalyticsDay]) -> [UsageClientRow]? {
        var aggregates: [String: UsageTokenTotals] = [:]
        for activity in days.flatMap(\.clients) {
            let current = aggregates[activity.clientID] ?? .zero
            guard let next = current.adding(activity.totals) else { return nil }
            aggregates[activity.clientID] = next
        }
        return aggregates.map { UsageClientRow(clientID: $0.key, totals: $0.value) }
            .sorted {
                $0.totalTokens == $1.totalTokens
                    ? $0.clientID < $1.clientID
                    : $0.totalTokens > $1.totalTokens
            }
    }
}

private struct ModelAggregate {
    let turns: Int64
    let chats: Int64
    let credits: Decimal

    static let zero = ModelAggregate(turns: 0, chats: 0, credits: 0)

    func adding(_ activity: UsageModelActivity) -> ModelAggregate? {
        guard let turns = checkedSum(turns, activity.turns),
              let chats = checkedSum(chats, activity.chats),
              let credits = checkedDecimalSum(credits, activity.credits) else { return nil }
        return ModelAggregate(turns: turns, chats: chats, credits: credits)
    }
}

extension UsageTokenTotals {
    static let zero = UsageTokenTotals(
        totalTokens: 0,
        uncachedInputTokens: 0,
        cachedInputTokens: 0,
        outputTokens: 0,
        turns: 0,
        chats: 0
    )

    func adding(_ other: UsageTokenTotals) -> UsageTokenTotals? {
        guard let totalTokens = checkedSum(totalTokens, other.totalTokens),
              let uncachedInputTokens = checkedSum(uncachedInputTokens, other.uncachedInputTokens),
              let cachedInputTokens = checkedSum(cachedInputTokens, other.cachedInputTokens),
              let outputTokens = checkedSum(outputTokens, other.outputTokens),
              let turns = checkedSum(turns, other.turns),
              let chats = checkedSum(chats, other.chats) else { return nil }
        return UsageTokenTotals(
            totalTokens: totalTokens,
            uncachedInputTokens: uncachedInputTokens,
            cachedInputTokens: cachedInputTokens,
            outputTokens: outputTokens,
            turns: turns,
            chats: chats
        )
    }
}

private func checkedSum(_ lhs: Int64, _ rhs: Int64) -> Int64? {
    let result = lhs.addingReportingOverflow(rhs)
    return result.overflow ? nil : result.partialValue
}

private func checkedDecimalSum(_ lhs: Decimal, _ rhs: Decimal) -> Decimal? {
    var lhs = lhs
    var rhs = rhs
    var result = Decimal()
    let error = NSDecimalAdd(&result, &lhs, &rhs, .plain)
    guard error == .noError || error == .lossOfPrecision,
          !result.isNaN else { return nil }
    return result
}
