import Foundation

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

struct UsageSnapshot: Equatable, Sendable {
    let windows: [UsageWindow]
    let availableResetCredits: Int?
    let nextResetCreditGrantedAt: Date?
    let nextResetCreditExpiry: Date?
    let fetchedAt: Date

    init(
        windows: [UsageWindow],
        availableResetCredits: Int? = nil,
        nextResetCreditGrantedAt: Date? = nil,
        nextResetCreditExpiry: Date? = nil,
        fetchedAt: Date = .now
    ) {
        self.windows = windows
        self.availableResetCredits = availableResetCredits
        self.nextResetCreditGrantedAt = nextResetCreditGrantedAt
        self.nextResetCreditExpiry = nextResetCreditExpiry
        self.fetchedAt = fetchedAt
    }

    var weeklyWindow: UsageWindow? {
        windows.first { window in
            if case .weekly = window.kind { return true }
            return false
        }
    }

    func adding(resetCreditDetails details: ResetCreditDetails) -> UsageSnapshot {
        let hasAvailableCredits = (availableResetCredits ?? 0) > 0
        return UsageSnapshot(
            windows: windows,
            availableResetCredits: availableResetCredits,
            nextResetCreditGrantedAt: hasAvailableCredits ? details.nextGrantedAt : nil,
            nextResetCreditExpiry: hasAvailableCredits ? details.nextExpiry : nil,
            fetchedAt: fetchedAt
        )
    }
}

struct ResetCreditDetails: Equatable, Sendable {
    let nextGrantedAt: Date?
    let nextExpiry: Date?
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
