import Foundation

enum ChatGPTPlan: Equatable, Sendable {
    case free
    case go
    case plus
    case pro
    case proLite
    case business
    case enterprise
    case edu

    init?(apiValue: String) {
        switch apiValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "free": self = .free
        case "go": self = .go
        case "plus": self = .plus
        case "pro": self = .pro
        case "prolite": self = .proLite
        case "business": self = .business
        case "enterprise": self = .enterprise
        case "edu": self = .edu
        default: return nil
        }
    }

    var displayName: String {
        switch self {
        case .free: "Free"
        case .go: "Go"
        case .plus: "Plus"
        case .pro: "Pro"
        case .proLite: "Pro Lite"
        case .business: "Business"
        case .enterprise: "Enterprise"
        case .edu: "Edu"
        }
    }
}

enum UsageWindowKind: Equatable, Sendable {
    case rolling(hours: Int)
    case daily
    case weekly
    case custom(seconds: Int)
}

struct UsageWindow: Equatable, Identifiable, Sendable {
    let id: String
    let kind: UsageWindowKind
    let usedPercent: Double
    let resetAt: Date?
    let durationSeconds: TimeInterval?

    init(
        id: String,
        kind: UsageWindowKind,
        usedPercent: Double,
        resetAt: Date? = nil,
        durationSeconds: TimeInterval? = nil
    ) {
        self.id = id
        self.kind = kind
        self.usedPercent = UsageWindowClassifier.clampPercent(usedPercent)
        self.resetAt = resetAt
        self.durationSeconds = durationSeconds
    }

    var remainingPercent: Double {
        max(0, 100 - usedPercent)
    }
}

struct NamedUsageWindow: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let window: UsageWindow
}

struct ResetCredit: Equatable, Identifiable, Sendable {
    let id: String
    let status: String
    let title: String?
    let grantedAt: Date?
    let expiresAt: Date?
    let isSupportedByPlan: Bool?
}

struct SpendControlSummary: Equatable, Sendable {
    let limit: Decimal
    let used: Decimal
    let remainingPercent: Double?
    let resetsAt: Date?
}

struct UsageSnapshot: Equatable, Sendable {
    let plan: ChatGPTPlan?
    let creditsRemaining: CreditsRemaining?
    let windows: [UsageWindow]
    let additionalWindows: [NamedUsageWindow]
    let codeReviewWindows: [NamedUsageWindow]
    let resetCredits: [ResetCredit]
    let spendControl: SpendControlSummary?
    private let reportedAvailableResetCredits: Int?
    let analyticsDataset: UsageAnalyticsDataset?
    let profileStats: CodexProfileStats?
    let fetchedAt: Date

    init(
        plan: ChatGPTPlan? = nil,
        creditsRemaining: CreditsRemaining? = nil,
        windows: [UsageWindow],
        additionalWindows: [NamedUsageWindow] = [],
        codeReviewWindows: [NamedUsageWindow] = [],
        resetCredits: [ResetCredit] = [],
        spendControl: SpendControlSummary? = nil,
        availableResetCredits: Int? = nil,
        nextResetCreditGrantedAt: Date? = nil,
        nextResetCreditExpiry: Date? = nil,
        analyticsDataset: UsageAnalyticsDataset? = nil,
        profileStats: CodexProfileStats? = nil,
        fetchedAt: Date = .now
    ) {
        self.plan = plan
        self.creditsRemaining = creditsRemaining
        self.windows = windows
        self.additionalWindows = additionalWindows
        self.codeReviewWindows = codeReviewWindows
        self.spendControl = spendControl
        self.reportedAvailableResetCredits = availableResetCredits
        if resetCredits.isEmpty,
           nextResetCreditGrantedAt != nil || nextResetCreditExpiry != nil {
            self.resetCredits = [ResetCredit(
                id: "legacy-next-reset-credit",
                status: "available",
                title: nil,
                grantedAt: nextResetCreditGrantedAt,
                expiresAt: nextResetCreditExpiry,
                isSupportedByPlan: true
            )]
        } else {
            self.resetCredits = resetCredits
        }
        self.analyticsDataset = analyticsDataset
        self.profileStats = profileStats
        self.fetchedAt = fetchedAt
    }

    var availableResetCredits: Int? {
        reportedAvailableResetCredits
    }

    var nextResetCreditGrantedAt: Date? {
        nextAvailableResetCredit?.grantedAt
    }

    var nextResetCreditExpiry: Date? {
        nextAvailableResetCredit?.expiresAt
    }

    var weeklyWindow: UsageWindow? {
        windows.first { window in
            if case .weekly = window.kind { return true }
            return false
        }
    }

    func adding(resetCredits newResetCredits: [ResetCredit]) -> UsageSnapshot {
        return UsageSnapshot(
            plan: plan,
            creditsRemaining: creditsRemaining,
            windows: windows,
            additionalWindows: additionalWindows,
            codeReviewWindows: codeReviewWindows,
            resetCredits: newResetCredits,
            spendControl: spendControl,
            availableResetCredits: availableResetCredits,
            analyticsDataset: analyticsDataset,
            profileStats: profileStats,
            fetchedAt: fetchedAt
        )
    }

    func adding(analyticsDataset newAnalyticsDataset: UsageAnalyticsDataset?) -> UsageSnapshot {
        UsageSnapshot(
            plan: plan,
            creditsRemaining: creditsRemaining,
            windows: windows,
            additionalWindows: additionalWindows,
            codeReviewWindows: codeReviewWindows,
            resetCredits: resetCredits,
            spendControl: spendControl,
            availableResetCredits: availableResetCredits,
            analyticsDataset: newAnalyticsDataset ?? analyticsDataset,
            profileStats: profileStats,
            fetchedAt: fetchedAt
        )
    }

    func adding(profileStats newProfileStats: CodexProfileStats?) -> UsageSnapshot {
        UsageSnapshot(
            plan: plan,
            creditsRemaining: creditsRemaining,
            windows: windows,
            additionalWindows: additionalWindows,
            codeReviewWindows: codeReviewWindows,
            resetCredits: resetCredits,
            spendControl: spendControl,
            availableResetCredits: availableResetCredits,
            analyticsDataset: analyticsDataset,
            profileStats: newProfileStats ?? profileStats,
            fetchedAt: fetchedAt
        )
    }

    private var nextAvailableResetCredit: ResetCredit? {
        resetCredits
            .filter { $0.status == "available" && $0.isSupportedByPlan != false }
            .filter { $0.expiresAt != nil }
            .min { lhs, rhs in
                lhs.expiresAt ?? .distantFuture < rhs.expiresAt ?? .distantFuture
            }
    }
}

enum CreditsRemaining: Equatable, Sendable {
    case balance(String)
    case unlimited

    var displayValue: String {
        switch self {
        case let .balance(value): value
        case .unlimited: "Unlimited"
        }
    }
}

enum WeeklyQuotaLevel: Equatable, Sendable {
    case healthy
    case warning
    case critical
    case unavailable

    init(weeklyWindow: UsageWindow?) {
        guard let weeklyWindow else {
            self = .unavailable
            return
        }
        self.init(remainingPercent: weeklyWindow.remainingPercent)
    }

    init(remainingPercent: Double) {
        guard remainingPercent.isFinite else {
            self = .critical
            return
        }
        if remainingPercent <= 10 {
            self = .critical
        } else if remainingPercent <= 20 {
            self = .warning
        } else {
            self = .healthy
        }
    }
}
