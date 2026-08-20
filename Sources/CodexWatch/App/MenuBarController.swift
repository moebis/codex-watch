import AppKit
import Foundation

final class MenuBarController: NSObject {
    static let refreshInterval: TimeInterval = 60

    private let statusItem: NSStatusItem
    private let authReader: CodexAuthReader
    private let session: URLSession
    private var refreshTimer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var snapshot: UsageSnapshot?
    private var errorState: MenuBarErrorState?
    private var lastAnalyticsAttempt: Date?

    init(
        statusItem: NSStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength),
        authReader: CodexAuthReader = CodexAuthReader(),
        session: URLSession = SecureUsageSession.make()
    ) {
        self.statusItem = statusItem
        self.authReader = authReader
        self.session = session
        super.init()
    }

    func start() {
        configureStatusButton()
        rebuildMenu()
        refresh(manual: true)
        refreshTimer = Timer.scheduledTimer(
            withTimeInterval: Self.refreshInterval,
            repeats: true
        ) { [weak self] _ in
            self?.refresh(manual: false)
        }
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        refreshTask?.cancel()
        refreshTask = nil
        session.invalidateAndCancel()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else { return }
        MenuBarButtonStyle.apply(to: button)
        button.title = MenuBarText.statusTitle(snapshot: nil)
    }

    @objc private func refreshNow() {
        refresh(manual: true)
    }

    private func refresh(manual: Bool) {
        refreshTask?.cancel()
        let reader = authReader
        let session = self.session
        let now = Date.now
        let shouldFetchAnalytics = AnalyticsRefreshPolicy.shouldRefresh(
            lastAttempt: lastAnalyticsAttempt,
            now: now,
            manual: manual
        )
        if shouldFetchAnalytics {
            lastAnalyticsAttempt = now
        }
        let previousAnalyticsDataset = snapshot?.analyticsDataset
        refreshTask = Task { [weak self] in
            do {
                let credentials = try reader.read()
                let client = CodexUsageClient(
                    credentials: credentials,
                    session: session
                )
                let quotaSnapshot = try await client.fetch()
                let analyticsDataset = shouldFetchAnalytics
                    ? try? await client.fetchAnalyticsDataset(referenceDate: now)
                    : previousAnalyticsDataset
                let value = quotaSnapshot.adding(
                    analyticsDataset: analyticsDataset ?? previousAnalyticsDataset
                )
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    self?.apply(snapshot: value)
                }
            } catch let error as CodexAuthError {
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    self?.apply(error: error == .authFileUnavailable ? .signInRequired : .quotaUnavailable)
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    self?.apply(error: .quotaUnavailable)
                }
            }
        }
    }

    private func apply(snapshot: UsageSnapshot) {
        self.snapshot = snapshot
        errorState = nil
        statusItem.button?.title = MenuBarText.statusTitle(snapshot: snapshot)
        rebuildMenu()
    }

    private func apply(error: MenuBarErrorState) {
        errorState = error
        if snapshot == nil {
            statusItem.button?.title = MenuBarText.statusTitle(snapshot: nil)
        }
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let progressItem = NSMenuItem()
        progressItem.view = QuotaProgressMenuView(
            presentation: QuotaProgressPresentation(
                snapshot: snapshot,
                error: errorState,
                now: .now
            )
        )
        menu.addItem(progressItem)

        if let dataset = snapshot?.analyticsDataset,
           let projection = UsageAnalyticsProjection.make(
               dataset: dataset,
               range: .days30,
               referenceDate: .now
           ) {
            menu.addItem(.separator())
            let analyticsItem = NSMenuItem()
            analyticsItem.view = UsageAnalyticsMenuView(
                presentation: UsageAnalyticsPresentation(projection: projection)
            )
            menu.addItem(analyticsItem)
        }

        menu.addItem(.separator())
        menu.addItem(actionItem(title: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r"))
        menu.addItem(actionItem(title: "Open ChatGPT", action: #selector(openChatGPT), keyEquivalent: "o"))
        menu.addItem(
            actionItem(
                title: "Open Usage Analytics…",
                action: #selector(openUsageAnalytics),
                keyEquivalent: ""
            )
        )
        menu.addItem(.separator())
        let versionItem = NSMenuItem(title: "Version \(AppIdentity.version)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        menu.addItem(.separator())
        menu.addItem(actionItem(title: "Quit Codex Watch", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func actionItem(title: String, action: Selector, keyEquivalent: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    @objc private func openChatGPT() {
        guard let appURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: AppIdentity.chatGPTCodexBundleIdentifier
        ) else { return }
        NSWorkspace.shared.open(appURL)
    }

    @objc private func openUsageAnalytics() {
        NSWorkspace.shared.open(AppIdentity.usageAnalyticsURL)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
