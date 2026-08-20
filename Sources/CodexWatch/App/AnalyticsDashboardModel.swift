import Combine
import Foundation

enum AnalyticsDashboardErrorState: Equatable, Sendable {
    case analyticsUnavailable

    var message: String {
        switch self {
        case .analyticsUnavailable:
            "Analytics refresh unavailable"
        }
    }
}

@MainActor
final class AnalyticsDashboardModel: ObservableObject {
    enum ModelError: Error, Equatable {
        case dataUnavailable
    }

    static let rangePreferenceKey = "codexWatch.analyticsRange"

    @Published var range: AnalyticsRange {
        didSet {
            defaults.set(range.rawValue, forKey: Self.rangePreferenceKey)
            reproject()
        }
    }
    @Published private(set) var projection: UsageAnalyticsProjection?
    @Published private(set) var isStale = false
    @Published private(set) var errorState: AnalyticsDashboardErrorState?

    private let defaults: UserDefaults
    private let calendar: Calendar
    private var dataset: UsageAnalyticsDataset?
    private var referenceDate = Date.now

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
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
        reproject()
    }

    func csvString() throws -> String {
        guard let projection else { throw ModelError.dataUnavailable }
        return try UsageAnalyticsCSVExporter.string(projection: projection)
    }

    var suggestedCSVFilename: String {
        UsageAnalyticsCSVExporter.suggestedFilename(
            range: range,
            dataThrough: projection?.dataThrough
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
    }
}
