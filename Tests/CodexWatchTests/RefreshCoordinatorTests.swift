import Foundation
import XCTest
@testable import CodexWatch

final class RefreshCoordinatorTests: XCTestCase {
    func testFailedCapabilityRefreshPreservesLastGoodValueAndMarksItStale() {
        let previous = profile(lifetimeTokens: 30_300_000_000)

        let resolved = CapabilityRefreshState.resolve(
            previous: previous,
            wasStale: false,
            attempt: CapabilityRefreshAttempt<CodexProfileStats>.failure
        )

        XCTAssertEqual(resolved.value, previous)
        XCTAssertTrue(resolved.isStale)
    }

    func testSuccessfulCapabilityRefreshReplacesValueAndClearsStaleState() {
        let previous = profile(lifetimeTokens: 30_300_000_000)
        let replacement = profile(lifetimeTokens: 30_400_000_000)

        let resolved = CapabilityRefreshState.resolve(
            previous: previous,
            wasStale: true,
            attempt: CapabilityRefreshAttempt.success(replacement)
        )
        let notAttempted = CapabilityRefreshState.resolve(
            previous: previous,
            wasStale: true,
            attempt: CapabilityRefreshAttempt<CodexProfileStats>.notAttempted
        )

        XCTAssertEqual(resolved.value, replacement)
        XCTAssertFalse(resolved.isStale)
        XCTAssertEqual(notAttempted.value, previous)
        XCTAssertTrue(notAttempted.isStale)
    }

    func testAdaptivePolicyUsesInteractionAndConstrainedDelays() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)

        XCTAssertEqual(AdaptiveRefreshPolicy.nextDelay(
            now: now,
            lastMenuOpenAt: now.addingTimeInterval(-60),
            lowPowerMode: false,
            thermalConstrained: false
        ), 120)
        XCTAssertEqual(AdaptiveRefreshPolicy.nextDelay(
            now: now,
            lastMenuOpenAt: nil,
            lowPowerMode: true,
            thermalConstrained: false
        ), 1_800)
        XCTAssertEqual(AdaptiveRefreshPolicy.nextDelay(
            now: now,
            lastMenuOpenAt: now.addingTimeInterval(-30 * 60),
            lowPowerMode: false,
            thermalConstrained: false
        ), 300)
        XCTAssertEqual(AdaptiveRefreshPolicy.nextDelay(
            now: now,
            lastMenuOpenAt: now.addingTimeInterval(-2 * 60 * 60),
            lowPowerMode: false,
            thermalConstrained: false
        ), 900)
        XCTAssertEqual(AdaptiveRefreshPolicy.nextDelay(
            now: now,
            lastMenuOpenAt: now.addingTimeInterval(-5 * 60 * 60),
            lowPowerMode: false,
            thermalConstrained: false
        ), 1_800)
    }

    func testUnconfiguredPreferencePersistsAdaptive() {
        let suiteName = "RefreshCoordinatorTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(RefreshFrequency.load(from: defaults), .adaptive)
        XCTAssertEqual(defaults.integer(forKey: RefreshFrequency.preferenceKey), -1)
    }

    func testAutomaticAnalyticsRequestsRespectFifteenMinuteFloor() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)

        XCTAssertFalse(RefreshPolicy.shouldIncludeAnalytics(
            trigger: .automatic,
            lastAttempt: now.addingTimeInterval(-899),
            now: now
        ))
        XCTAssertTrue(RefreshPolicy.shouldIncludeAnalytics(
            trigger: .automatic,
            lastAttempt: now.addingTimeInterval(-900),
            now: now
        ))
        XCTAssertTrue(RefreshPolicy.shouldIncludeAnalytics(
            trigger: .manual,
            lastAttempt: now,
            now: now
        ))
    }

    func testStaleQuotaCopyUsesLastSuccessfulFetchTime() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)

        XCTAssertEqual(
            MenuBarText.updatedLine(lastUpdated: now.addingTimeInterval(-125), now: now),
            "Updated 2m ago"
        )
    }

    @MainActor
    func testAutomaticTriggersCoalesceIntoOneFetch() async {
        let gate = FetchGate()
        let coordinator = makeCoordinator(gate: gate)

        coordinator.trigger(.automatic)
        coordinator.trigger(.automatic)
        await gate.waitForFetchCount(1)
        await gate.release(trigger: .automatic)
        await coordinator.waitUntilIdleForTesting()

        let fetchCount = await gate.fetchCountValue()
        XCTAssertEqual(fetchCount, 1)
        coordinator.stop()
    }

    @MainActor
    func testManualReplacementPreventsOldGenerationPublishing() async {
        let gate = FetchGate()
        var publishedIDs: [String] = []
        let coordinator = makeCoordinator(gate: gate, publish: { result in
            if let id = result.snapshot?.windows.first?.id {
                publishedIDs.append(id)
            }
        })

        coordinator.trigger(.automatic)
        await gate.waitForFetchCount(1)
        coordinator.trigger(.manual)
        await gate.waitForFetchCount(2)
        await gate.release(trigger: .manual)
        await coordinator.waitUntilIdleForTesting()
        await gate.release(trigger: .automatic)
        for _ in 0 ..< 10 { await Task.yield() }

        XCTAssertEqual(publishedIDs, ["manual"])
        coordinator.stop()
    }

    @MainActor
    func testMenuOpenOnlyRefreshesSnapshotOlderThanSixtySeconds() async {
        let gate = FetchGate()
        let clock = TestClock(Date(timeIntervalSince1970: 2_000_000_000))
        let coordinator = makeCoordinator(gate: gate, now: { clock.now })

        coordinator.trigger(.automatic)
        await gate.waitForFetchCount(1)
        await gate.release(trigger: .automatic)
        await coordinator.waitUntilIdleForTesting()

        clock.now.addTimeInterval(60)
        coordinator.trigger(.menuOpened)
        for _ in 0 ..< 10 { await Task.yield() }
        let freshFetchCount = await gate.fetchCountValue()
        XCTAssertEqual(freshFetchCount, 1)

        clock.now.addTimeInterval(1)
        coordinator.trigger(.menuOpened)
        await gate.waitForFetchCount(2)
        let lastTrigger = await gate.lastTrigger()
        XCTAssertEqual(lastTrigger, .menuOpened)
        await gate.release(trigger: .menuOpened)
        await coordinator.waitUntilIdleForTesting()
        coordinator.stop()
    }

    @MainActor
    func testStopPreventsPendingPublication() async {
        let gate = FetchGate()
        var publicationCount = 0
        let coordinator = makeCoordinator(
            gate: gate,
            publish: { _ in publicationCount += 1 }
        )

        coordinator.trigger(.automatic)
        await gate.waitForFetchCount(1)
        coordinator.stop()
        await gate.release(trigger: .automatic)
        for _ in 0 ..< 10 { await Task.yield() }

        XCTAssertEqual(publicationCount, 0)
    }

    @MainActor
    func testFixedScheduleDelayStartsOnlyAfterFetchCompletes() async {
        let gate = FetchGate()
        let sleeps = SleepRecorder()
        let coordinator = makeCoordinator(
            gate: gate,
            frequency: .oneMinute,
            sleep: { delay in
                await sleeps.record(delay)
                try await Task.sleep(nanoseconds: UInt64.max)
            }
        )

        coordinator.trigger(.automatic)
        await gate.waitForFetchCount(1)
        let sleepsBeforeCompletion = await sleeps.countValue()
        XCTAssertEqual(sleepsBeforeCompletion, 0)

        await gate.release(trigger: .automatic)
        await coordinator.waitUntilIdleForTesting()
        await sleeps.waitForCount(1)
        let delays = await sleeps.delaysValue()
        XCTAssertEqual(delays, [60])
        coordinator.stop()
    }

    @MainActor
    func testFreshMenuOpenReschedulesAdaptiveDelayFromInteractionTime() async {
        let gate = FetchGate()
        let sleeps = SleepRecorder()
        let clock = TestClock(Date(timeIntervalSince1970: 2_000_000_000))
        let coordinator = makeCoordinator(
            gate: gate,
            frequency: .adaptive,
            now: { clock.now },
            sleep: { delay in
                await sleeps.record(delay)
                try await Task.sleep(nanoseconds: UInt64.max)
            }
        )

        coordinator.trigger(.automatic)
        await gate.waitForFetchCount(1)
        await gate.release(trigger: .automatic)
        await coordinator.waitUntilIdleForTesting()
        await sleeps.waitForCount(1)

        clock.now.addTimeInterval(30)
        coordinator.trigger(.menuOpened)
        for _ in 0 ..< 100 { await Task.yield() }

        let fetchCount = await gate.fetchCountValue()
        let delays = await sleeps.delaysValue()
        XCTAssertEqual(fetchCount, 1)
        XCTAssertEqual(delays, [1_800, 120])
        coordinator.stop()
    }

    @MainActor
    private func makeCoordinator(
        gate: FetchGate,
        frequency: RefreshFrequency = .manual,
        now: @escaping @MainActor () -> Date = { Date(timeIntervalSince1970: 2_000_000_000) },
        sleep: @escaping RefreshCoordinator.Sleep = { _ in },
        publish: @escaping @MainActor @Sendable (RefreshResult) -> Void = { _ in }
    ) -> RefreshCoordinator {
        RefreshCoordinator(
            frequency: frequency,
            now: now,
            sleep: sleep,
            fetch: { request in await gate.fetch(request) },
            publish: publish
        )
    }

    private func profile(lifetimeTokens: Int64) -> CodexProfileStats {
        CodexProfileStats(
            lifetimeTokens: lifetimeTokens,
            peakDailyTokens: nil,
            longestRunningTurnSeconds: nil,
            currentStreakDays: nil,
            longestStreakDays: nil,
            dailyBuckets: [],
            insights: CodexProfileInsights(
                fastModePercent: nil,
                reasoningEffort: nil,
                reasoningEffortPercent: nil,
                uniqueSkillsUsed: nil,
                totalSkillsUsed: nil,
                totalChats: nil
            ),
            invocations: [],
            fetchedAt: Date(timeIntervalSince1970: 100)
        )
    }
}

@MainActor
private final class TestClock {
    var now: Date

    init(_ now: Date) {
        self.now = now
    }
}

private actor SleepRecorder {
    private var delays: [TimeInterval] = []

    func record(_ delay: TimeInterval) {
        delays.append(delay)
    }

    func countValue() -> Int { delays.count }

    func delaysValue() -> [TimeInterval] { delays }

    func waitForCount(_ count: Int) async {
        while delays.count < count { await Task.yield() }
    }
}

private actor FetchGate {
    private(set) var requests: [RefreshRequest] = []
    private var continuations: [Int: CheckedContinuation<Void, Never>] = [:]

    var fetchCount: Int { requests.count }

    func fetchCountValue() -> Int { requests.count }

    func lastTrigger() -> RefreshTrigger? { requests.last?.trigger }

    func fetch(_ request: RefreshRequest) async -> RefreshResult {
        requests.append(request)
        await withCheckedContinuation { continuation in
            continuations[request.generation] = continuation
        }
        let id = request.trigger == .manual ? "manual" : "automatic"
        return RefreshResult(
            snapshot: UsageSnapshot(
                windows: [UsageWindow(id: id, kind: .weekly, usedPercent: 0)],
                fetchedAt: Date(timeIntervalSince1970: 2_000_000_000)
            ),
            error: nil,
            analyticsStale: false
        )
    }

    func waitForFetchCount(_ count: Int) async {
        while requests.count < count { await Task.yield() }
    }

    func release(trigger: RefreshTrigger) {
        guard let request = requests.last(where: { $0.trigger == trigger }),
              let continuation = continuations.removeValue(forKey: request.generation) else { return }
        continuation.resume()
    }
}
