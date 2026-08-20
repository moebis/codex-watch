import Foundation

struct UsageAnalyticsSummary: Equatable, Sendable {
    let periodStart: Date
    let periodEnd: Date
    let totalTokens: Int64
    let uncachedInputTokens: Int64
    let cachedInputTokens: Int64
    let outputTokens: Int64
    let turns: Int64
    let chats: Int64
    let fetchedAt: Date
}
