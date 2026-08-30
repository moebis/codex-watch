import CoreGraphics
import Foundation

enum UsageHeatmapPresentation {
    nonisolated static func accessibilityText(_ day: UsageDayCell) -> String {
        switch day.state {
        case let .observed(totals):
            return "\(dateText(day.date)), observed, \(totals.totalTokens) tokens"
        case let .activityOnly(turns, chats):
            return "\(dateText(day.date)), activity only, \(turns) turns, \(chats) chats, token totals unavailable"
        case .missing:
            return "\(dateText(day.date)), missing"
        }
    }

    private nonisolated static func dateText(_ date: Date) -> String {
        date.formatted(
            .dateTime.year().month(.abbreviated).day()
                .locale(Locale(identifier: "en_US_POSIX"))
        )
    }
}

struct UsageHeatmapLayout: Equatable, Sendable {
    struct Cell: Equatable, Identifiable, Sendable {
        let day: UsageDayCell
        let row: Int
        let column: Int

        var id: Date { day.id }
    }

    struct Slot: Equatable, Identifiable, Sendable {
        let index: Int
        let row: Int
        let column: Int
        let day: UsageDayCell?

        var id: Int { index }
    }

    let cells: [Cell]
    let slots: [Slot]
    let leadingPaddingCount: Int
    let columnCount: Int

    init(days: [UsageDayCell], calendar: Calendar) {
        let chronologicalDays = days.sorted { $0.date < $1.date }
        guard let firstDate = chronologicalDays.first?.date else {
            cells = []
            slots = []
            leadingPaddingCount = 0
            columnCount = 0
            return
        }

        let firstDay = calendar.component(.weekday, from: firstDate)
        let leadingPaddingCount = (firstDay - calendar.firstWeekday + 7) % 7
        let columnCount = (leadingPaddingCount + chronologicalDays.count + 6) / 7
        self.leadingPaddingCount = leadingPaddingCount
        self.columnCount = columnCount

        cells = chronologicalDays.enumerated().map { offset, day in
            let slotIndex = leadingPaddingCount + offset
            return Cell(
                day: day,
                row: slotIndex % 7,
                column: slotIndex / 7
            )
        }
        slots = (0 ..< columnCount * 7).map { index in
            let dayIndex = index - leadingPaddingCount
            return Slot(
                index: index,
                row: index % 7,
                column: index / 7,
                day: chronologicalDays.indices.contains(dayIndex)
                    ? chronologicalDays[dayIndex]
                    : nil
            )
        }
    }
}

struct DashboardTableLayout: Equatable, Sendable {
    struct Column: Equatable, Sendable {
        let title: String
        let width: CGFloat
    }

    enum Placement: Equatable, Sendable {
        case fits(contentWidth: CGFloat)
        case horizontallyScrollable(contentWidth: CGFloat)
    }

    static let modelActivity = DashboardTableLayout(columns: [
        Column(title: "Model", width: 220),
        Column(title: "Turns", width: 80),
        Column(title: "Chats", width: 80),
        Column(title: "Credits", width: 90),
        Column(title: "Turn share", width: 90)
    ])

    static let clientTokens = DashboardTableLayout(columns: [
        Column(title: "Client", width: 190),
        Column(title: "Total", width: 90),
        Column(title: "Input", width: 90),
        Column(title: "Cached", width: 90),
        Column(title: "Output", width: 90),
        Column(title: "Turns", width: 70),
        Column(title: "Chats", width: 70)
    ])

    let columns: [Column]
    let spacing: CGFloat

    init(columns: [Column], spacing: CGFloat = 12) {
        self.columns = columns
        self.spacing = spacing
    }

    var contentWidth: CGFloat {
        columns.reduce(0) { $0 + $1.width }
            + CGFloat(max(0, columns.count - 1)) * spacing
    }

    func placement(in viewportWidth: CGFloat) -> Placement {
        contentWidth <= viewportWidth
            ? .fits(contentWidth: contentWidth)
            : .horizontallyScrollable(contentWidth: contentWidth)
    }
}
