import AppKit
import Foundation

enum AnalyticsRefreshPolicy {
    static let interval: TimeInterval = 15 * 60

    static func shouldRefresh(lastAttempt: Date?, now: Date, manual: Bool) -> Bool {
        guard !manual else { return true }
        guard let lastAttempt else { return true }
        return now.timeIntervalSince(lastAttempt) >= interval
    }
}

struct UsageAnalyticsPresentation: Equatable {
    let title = "Last 30 days"
    let totalTokens: String
    let inputTokens: String
    let cachedInputTokens: String
    let outputTokens: String
    let turns: String
    let chats: String

    init(summary: UsageAnalyticsSummary) {
        totalTokens = Self.compact(summary.totalTokens)
        inputTokens = Self.compact(summary.uncachedInputTokens)
        cachedInputTokens = Self.compact(summary.cachedInputTokens)
        outputTokens = Self.compact(summary.outputTokens)
        turns = Self.compact(summary.turns)
        chats = Self.compact(summary.chats)
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
}

final class UsageAnalyticsMenuView: NSView {
    static let width: CGFloat = 260
    static let height: CGFloat = 170

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
            Self.labelRow(title: "Chats", value: presentation.chats)
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
