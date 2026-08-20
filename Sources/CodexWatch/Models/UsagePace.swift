import Foundation

struct UsagePace: Equatable, Sendable {
    let deltaPercent: Double
    let expectedUsedPercent: Double
    let actualUsedPercent: Double
    let projectedExhaustion: Date?
    let willLastToReset: Bool

    static func calculate(window: UsageWindow, now: Date) -> UsagePace? {
        guard let resetAt = window.resetAt,
              let duration = window.durationSeconds,
              duration.isFinite,
              duration > 0 else { return nil }

        let timeUntilReset = resetAt.timeIntervalSince(now)
        guard timeUntilReset.isFinite,
              timeUntilReset > 0,
              timeUntilReset <= duration else { return nil }

        let elapsed = duration - timeUntilReset
        let elapsedFraction = elapsed / duration
        guard elapsedFraction >= 0.03 else { return nil }

        let expectedUsedPercent = elapsedFraction * 100
        let actualUsedPercent = min(100, max(0, window.usedPercent))
        let observedRate = actualUsedPercent / elapsed

        let projectedExhaustion: Date?
        if observedRate > 0 {
            let secondsUntilExhaustion = (100 - actualUsedPercent) / observedRate
            projectedExhaustion = secondsUntilExhaustion < timeUntilReset
                ? now.addingTimeInterval(max(0, secondsUntilExhaustion))
                : nil
        } else {
            projectedExhaustion = nil
        }

        return UsagePace(
            deltaPercent: actualUsedPercent - expectedUsedPercent,
            expectedUsedPercent: expectedUsedPercent,
            actualUsedPercent: actualUsedPercent,
            projectedExhaustion: projectedExhaustion,
            willLastToReset: projectedExhaustion == nil
        )
    }
}
