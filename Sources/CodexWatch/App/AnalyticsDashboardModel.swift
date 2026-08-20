import Combine
import Foundation

enum AnalyticsDashboardErrorState: Equatable, Sendable {
    case analyticsUnavailable
    case profileUnavailable

    var message: String {
        switch self {
        case .analyticsUnavailable:
            "Analytics refresh unavailable"
        case .profileUnavailable:
            "Lifetime refresh unavailable"
        }
    }
}

enum AnalyticsDashboardSection: String, CaseIterable, Identifiable, Sendable {
    case usage
    case lifetime

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

@MainActor
final class AnalyticsDashboardModel: ObservableObject {
    enum ModelError: Error, Equatable {
        case dataUnavailable
    }

    static let rangePreferenceKey = "codexWatch.analyticsRange"
    static let sectionPreferenceKey = "codexWatch.analyticsSection"

    @Published var section: AnalyticsDashboardSection {
        didSet {
            defaults.set(section.rawValue, forKey: Self.sectionPreferenceKey)
        }
    }

    @Published var range: AnalyticsRange {
        didSet {
            defaults.set(range.rawValue, forKey: Self.rangePreferenceKey)
            reproject()
        }
    }
    @Published private(set) var projection: UsageAnalyticsProjection?
    @Published private(set) var isStale = false
    @Published private(set) var errorState: AnalyticsDashboardErrorState?
    @Published private(set) var lifetime: LifetimeDashboardModel?
    @Published private(set) var profileIsStale = false
    @Published private(set) var profileErrorState: AnalyticsDashboardErrorState?

    private let defaults: UserDefaults
    private let calendar: Calendar
    private var dataset: UsageAnalyticsDataset?
    private var profileStats: CodexProfileStats?
    private var referenceDate = Date.now

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
        if let rawSection = defaults.string(forKey: Self.sectionPreferenceKey),
           let restoredSection = AnalyticsDashboardSection(rawValue: rawSection) {
            section = restoredSection
        } else {
            section = .usage
            defaults.set(AnalyticsDashboardSection.usage.rawValue, forKey: Self.sectionPreferenceKey)
        }
        let stored = defaults.integer(forKey: Self.rangePreferenceKey)
        if defaults.object(forKey: Self.rangePreferenceKey) != nil,
           let restored = AnalyticsRange(rawValue: stored) {
            range = restored
        } else {
            range = .days30
            defaults.set(AnalyticsRange.days30.rawValue, forKey: Self.rangePreferenceKey)
        }
    }

    func update(
        dataset newDataset: UsageAnalyticsDataset?,
        error: AnalyticsDashboardErrorState?,
        profileStats newProfileStats: CodexProfileStats? = nil,
        profileError: AnalyticsDashboardErrorState? = nil,
        now: Date
    ) {
        referenceDate = now
        if let newDataset {
            dataset = newDataset
            isStale = error != nil
        } else if error != nil, dataset != nil {
            isStale = true
        }
        errorState = error
        if let newProfileStats {
            profileStats = newProfileStats
            profileIsStale = profileError != nil
        } else if profileError != nil, profileStats != nil {
            profileIsStale = true
        }
        profileErrorState = profileError
        reproject()
    }

    func csvString() throws -> String {
        guard let projection else { throw ModelError.dataUnavailable }
        return try UsageAnalyticsCSVExporter.string(projection: projection, calendar: calendar)
    }

    var suggestedCSVFilename: String {
        UsageAnalyticsCSVExporter.suggestedFilename(
            range: range,
            dataThrough: projection?.dataThrough,
            calendar: calendar
        )
    }

    private func reproject() {
        projection = dataset.flatMap {
            UsageAnalyticsProjection.make(
                dataset: $0,
                range: range,
                referenceDate: referenceDate,
                calendar: calendar
            )
        }
        lifetime = profileStats.map { LifetimeDashboardModel(profile: $0) }
    }
}
