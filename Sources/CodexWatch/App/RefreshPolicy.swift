import Foundation

enum RefreshFrequency: Int, CaseIterable, Sendable {
    case manual = 0
    case oneMinute = 60
    case twoMinutes = 120
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case thirtyMinutes = 1_800
    case adaptive = -1

    static let preferenceKey = "codexWatch.refreshFrequency"

    static func load(from defaults: UserDefaults = .standard) -> RefreshFrequency {
        guard defaults.object(forKey: preferenceKey) != nil,
              let stored = RefreshFrequency(rawValue: defaults.integer(forKey: preferenceKey)) else {
            defaults.set(RefreshFrequency.adaptive.rawValue, forKey: preferenceKey)
            return .adaptive
        }
        return stored
    }

    func persist(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.preferenceKey)
    }

    var displayName: String {
        switch self {
        case .manual: "Manual"
        case .oneMinute: "1 Minute"
        case .twoMinutes: "2 Minutes"
        case .fiveMinutes: "5 Minutes"
        case .fifteenMinutes: "15 Minutes"
        case .thirtyMinutes: "30 Minutes"
        case .adaptive: "Adaptive"
        }
    }
}

enum RefreshTrigger: Equatable, Sendable {
    case automatic
    case manual
    case menuOpened
    case wake

    var replacesActiveWork: Bool {
        self == .manual
    }
}

struct RefreshRequest: Equatable, Sendable {
    let generation: Int
    let trigger: RefreshTrigger
    let includeAnalytics: Bool
    let requestedAt: Date
}

struct RefreshResult: Equatable, Sendable {
    let snapshot: UsageSnapshot?
    let error: MenuBarErrorState?
    let analyticsStale: Bool
    let profileStale: Bool

    init(
        snapshot: UsageSnapshot?,
        error: MenuBarErrorState?,
        analyticsStale: Bool,
        profileStale: Bool = false
    ) {
        self.snapshot = snapshot
        self.error = error
        self.analyticsStale = analyticsStale
        self.profileStale = profileStale
    }
}

enum CapabilityRefreshAttempt<Value> {
    case notAttempted
    case success(Value)
    case failure
}

struct CapabilityRefreshState<Value> {
    let value: Value?
    let isStale: Bool

    static func resolve(
        previous: Value?,
        wasStale: Bool,
        attempt: CapabilityRefreshAttempt<Value>
    ) -> CapabilityRefreshState<Value> {
        switch attempt {
        case .notAttempted:
            return CapabilityRefreshState(value: previous, isStale: wasStale)
        case let .success(value):
            return CapabilityRefreshState(value: value, isStale: false)
        case .failure:
            return CapabilityRefreshState(value: previous, isStale: previous != nil)
        }
    }
}

enum RefreshPolicy {
    static let analyticsInterval: TimeInterval = 15 * 60
    static let menuOpenFreshness: TimeInterval = 60

    static func shouldIncludeAnalytics(
        trigger: RefreshTrigger,
        lastAttempt: Date?,
        now: Date
    ) -> Bool {
        if trigger == .manual { return true }
        guard let lastAttempt else { return true }
        return now.timeIntervalSince(lastAttempt) >= analyticsInterval
    }
}

enum AdaptiveRefreshPolicy {
    static func nextDelay(
        now: Date,
        lastMenuOpenAt: Date?,
        lowPowerMode: Bool,
        thermalConstrained: Bool
    ) -> TimeInterval {
        if lowPowerMode || thermalConstrained { return 30 * 60 }
        guard let lastMenuOpenAt else { return 30 * 60 }

        let elapsed = max(0, now.timeIntervalSince(lastMenuOpenAt))
        if elapsed <= 5 * 60 { return 2 * 60 }
        if elapsed <= 60 * 60 { return 5 * 60 }
        if elapsed <= 4 * 60 * 60 { return 15 * 60 }
        return 30 * 60
    }
}
