import AppKit
import Foundation

struct UsageAnalyticsPresentation: Equatable {
    let title = "Last 30 days"
    let totalTokens: String
    let inputTokens: String
    let cachedInputTokens: String
    let outputTokens: String
    let turns: String
    let chats: String
    let coverage: String
    let dataThrough: String

    init(projection: UsageAnalyticsProjection) {
        totalTokens = Self.compact(projection.totalTokens)
        inputTokens = Self.compact(projection.uncachedInputTokens)
        cachedInputTokens = Self.compact(projection.cachedInputTokens)
        outputTokens = Self.compact(projection.outputTokens)
        turns = Self.compact(projection.turns)
        chats = Self.compact(projection.chats)
        coverage = "\(projection.observedDayCount)/\(projection.requestedDayCount) days"
        dataThrough = projection.dataThrough.map(Self.dateFormatter.string(from:)) ?? "Unavailable"
    }

    private static func compact(_ value: Int64) -> String {
        let units: [(threshold: Double, suffix: String)] = [
            (1_000_000_000, "B"),
            (1_000_000, "M"),
            (1_000, "K")
        ]
        let numeric = Double(value)
        guard let unit = units.first(where: { numeric >= $0.threshold }) else {
            return String(value)
        }
        let scaled = numeric / unit.threshold
        let text = String(format: scaled >= 100 ? "%.0f" : "%.1f", scaled)
            .replacingOccurrences(of: ".0", with: "")
        return text + unit.suffix
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()
}

final class UsageAnalyticsMenuView: NSView {
    static let width: CGFloat = 260
    static let height: CGFloat = 210

    init(presentation: UsageAnalyticsPresentation) {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: Self.height))
        translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: presentation.title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor

        let rows = [
            Self.labelRow(title: "Total tokens", value: presentation.totalTokens),
            Self.labelRow(title: "Input tokens", value: presentation.inputTokens),
            Self.labelRow(title: "Cached input", value: presentation.cachedInputTokens),
            Self.labelRow(title: "Output tokens", value: presentation.outputTokens),
            Self.labelRow(title: "Turns", value: presentation.turns),
            Self.labelRow(title: "Chats", value: presentation.chats),
            Self.labelRow(title: "Coverage", value: presentation.coverage),
            Self.labelRow(title: "Data through", value: presentation.dataThrough)
        ]
        let stack = NSStackView(views: [titleLabel] + rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        for row in rows {
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.width),
            heightAnchor.constraint(equalToConstant: Self.height),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 10)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func labelRow(title: String, value: String) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 12, weight: .regular)
        titleLabel.textColor = .labelColor

        let valueLabel = NSTextField(labelWithString: value)
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = NSStackView(views: [titleLabel, valueLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }
}
