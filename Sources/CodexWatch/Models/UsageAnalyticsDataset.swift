import Foundation

struct UsageAnalyticsDataset: Equatable, Sendable {
    let requestedStart: Date
    let requestedEnd: Date
    let days: [UsageAnalyticsDay]
    let fetchedAt: Date
    let modelBreakdownIsPartial: Bool
    let clientBreakdownIsPartial: Bool

    var dataThrough: Date? { days.last?.date }
    var observedDates: Set<Date> { Set(days.map(\.date)) }
}

struct UsageAnalyticsDay: Equatable, Sendable {
    let date: Date
    let totals: UsageTokenTotals
    let models: [UsageModelActivity]
    let clients: [UsageClientActivity]
    let tokenDataIsAvailable: Bool

    init(
        date: Date,
        totals: UsageTokenTotals,
        models: [UsageModelActivity],
        clients: [UsageClientActivity],
        tokenDataIsAvailable: Bool = true
    ) {
        self.date = date
        self.totals = totals
        self.models = models
        self.clients = clients
        self.tokenDataIsAvailable = tokenDataIsAvailable
    }
}

struct UsageTokenTotals: Equatable, Sendable {
    let totalTokens: Int64
    let uncachedInputTokens: Int64
    let cachedInputTokens: Int64
    let outputTokens: Int64
    let turns: Int64
    let chats: Int64
}

struct UsageModelActivity: Equatable, Sendable {
    let model: String
    let turns: Int64
    let chats: Int64
    let credits: Decimal
}

struct UsageClientActivity: Equatable, Sendable {
    let clientID: String
    let totals: UsageTokenTotals
}
