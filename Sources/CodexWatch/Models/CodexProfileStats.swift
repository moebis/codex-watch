import Foundation

struct CodexProfileStats: Equatable, Sendable {
    let lifetimeTokens: Int64?
    let peakDailyTokens: Int64?
    let longestRunningTurnSeconds: Int64?
    let currentStreakDays: Int?
    let longestStreakDays: Int?
    let dailyBuckets: [CodexProfileDailyBucket]
    let insights: CodexProfileInsights
    let invocations: [CodexProfileInvocation]
    let fetchedAt: Date
}

struct CodexProfileDailyBucket: Equatable, Identifiable, Sendable {
    let date: Date
    let tokens: Int64

    var id: Date { date }
}

struct CodexProfileInsights: Equatable, Sendable {
    let fastModePercent: Double?
    let reasoningEffort: String?
    let reasoningEffortPercent: Double?
    let uniqueSkillsUsed: Int?
    let totalSkillsUsed: Int64?
    let totalChats: Int64?
}

struct CodexProfileInvocation: Equatable, Identifiable, Sendable {
    enum Kind: String, Equatable, Sendable {
        case plugin
        case skill
    }

    let id: String
    let displayName: String
    let kind: Kind
    let usageCount: Int64
}
