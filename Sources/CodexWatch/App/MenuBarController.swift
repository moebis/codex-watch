import AppKit
import Foundation

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let authReader: CodexAuthReader
    private let session: URLSession
    private let defaults: UserDefaults
    private let persistRefreshFrequency: (RefreshFrequency) -> Void
    private var coordinator: RefreshCoordinator!
    private var snapshot: UsageSnapshot?
    private var errorState: MenuBarErrorState?
    private(set) var analyticsStale = false
    private(set) var profileStale = false
    private var menuAnalyticsSection: MenuAnalyticsSection
    private var analyticsWindowController: AnalyticsWindowController?

    init(
        statusItem: NSStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength),
        authReader: CodexAuthReader = CodexAuthReader(),
        session: URLSession = SecureUsageSession.make(),
        defaults: UserDefaults = .standard,
        refreshFrequency: RefreshFrequency = .adaptive,
        persistRefreshFrequency: @escaping (RefreshFrequency) -> Void = { _ in }
    ) {
        self.statusItem = statusItem
        self.authReader = authReader
        self.session = session
        self.defaults = defaults
        menuAnalyticsSection = MenuAnalyticsSection.load(from: defaults)
        self.persistRefreshFrequency = persistRefreshFrequency
        super.init()
        coordinator = RefreshCoordinator(
            frequency: refreshFrequency,
            fetch: { [weak self] request in
                guard let self else {
                    return RefreshResult(
                        snapshot: nil,
                        error: nil,
                        analyticsStale: false,
                        profileStale: false
                    )
                }
                return await self.fetch(request: request)
            },
            publish: { [weak self] result in
                self?.apply(result: result)
            }
        )
    }

    func start() {
        configureStatusButton()
        rebuildMenu()
        coordinator.trigger(.manual)
    }

    func stop() {
        coordinator.stop()
        session.invalidateAndCancel()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    func wake() {
        coordinator.trigger(.wake)
    }

    func menuWillOpen(_ menu: NSMenu) {
        coordinator.trigger(.menuOpened)
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else { return }
        MenuBarButtonStyle.apply(to: button)
        button.title = MenuBarText.statusTitle(snapshot: nil)
    }

    @objc private func refreshNow() {
        coordinator.trigger(.manual)
    }

    @objc private func setRefreshFrequency(_ sender: NSMenuItem) {
        guard let rawValue = (sender.representedObject as? NSNumber)?.intValue,
              let frequency = RefreshFrequency(rawValue: rawValue) else { return }
        persistRefreshFrequency(frequency)
        coordinator.setFrequency(frequency)
        rebuildMenu()
    }

    private func fetch(request: RefreshRequest) async -> RefreshResult {
        do {
            let credentials = try authReader.read()
            let client = CodexUsageClient(credentials: credentials, session: session)
            return await RefreshBatch.execute(
                previousSnapshot: snapshot,
                analyticsWasStale: analyticsStale,
                profileWasStale: profileStale,
                includeAnalytics: request.includeAnalytics,
                requestedAt: request.requestedAt,
                quota: {
                    await Self.fetchQuota(client: client)
                },
                analytics: {
                    await Self.fetchAnalytics(
                        client: client,
                        referenceDate: request.requestedAt
                    )
                },
                profile: {
                    await Self.fetchProfile(
                        client: client,
                        referenceDate: request.requestedAt
                    )
                }
            )
        } catch is CodexAuthError {
            return RefreshResult(
                snapshot: nil,
                error: .signInRequired,
                analyticsStale: analyticsStale,
                profileStale: profileStale
            )
        } catch {
            return RefreshResult(
                snapshot: nil,
                error: .signInRequired,
                analyticsStale: analyticsStale,
                profileStale: profileStale
            )
        }
    }

    func apply(result: RefreshResult) {
        analyticsStale = result.analyticsStale
        profileStale = result.profileStale
        if let value = result.snapshot {
            snapshot = value
        }
        if result.snapshot != nil || result.error != nil {
            errorState = result.error
        }
        updateStatusButton()
        analyticsWindowController?.update(
            dataset: snapshot?.analyticsDataset,
            errorState: dashboardErrorState,
            profileStats: snapshot?.profileStats,
            profileErrorState: profileDashboardErrorState
        )
        rebuildMenu()
    }

    private static func fetchAnalytics(
        client: CodexUsageClient,
        referenceDate: Date
    ) async -> CapabilityRefreshAttempt<UsageAnalyticsDataset> {
        do {
            return .success(try await client.fetchAnalyticsDataset(referenceDate: referenceDate))
        } catch {
            return .failure
        }
    }

    private static func fetchQuota(client: CodexUsageClient) async -> QuotaRefreshAttempt {
        do {
            return .success(try await client.fetch())
        } catch CodexUsageError.reauthenticationRequired {
            return .failure(.signInRequired)
        } catch {
            return .failure(.quotaUnavailable)
        }
    }

    private static func fetchProfile(
        client: CodexUsageClient,
        referenceDate: Date
    ) async -> CapabilityRefreshAttempt<CodexProfileStats> {
        do {
            return .success(try await client.fetchProfileStats(referenceDate: referenceDate))
        } catch {
            return .failure
        }
    }

    private func updateStatusButton() {
        guard let button = statusItem.button else { return }
        button.title = MenuBarText.statusTitle(snapshot: snapshot)
        let isStale = errorState != nil && snapshot != nil
        MenuBarButtonStyle.applyRefreshState(to: button, isStale: isStale)
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self
        let progressItem = NSMenuItem()
        progressItem.view = QuotaProgressMenuView(
            presentation: QuotaProgressPresentation(
                snapshot: snapshot,
                error: errorState,
                now: .now
            )
        )
        menu.addItem(progressItem)

        let usagePresentation = snapshot?.analyticsDataset.flatMap { dataset in
            UsageAnalyticsProjection.make(
                dataset: dataset,
                range: .days30,
                referenceDate: .now
            ).map { projection in
                UsageAnalyticsPresentation(
                    projection: projection,
                    isStale: analyticsStale
                )
            }
        }
        let lifetimePresentation = snapshot?.profileStats.map { profile in
            LifetimeAnalyticsPresentation(
                model: LifetimeDashboardModel(profile: profile),
                isStale: profileStale
            )
        }

        if usagePresentation != nil || lifetimePresentation != nil {
            menu.addItem(.separator())
            let analyticsItem = NSMenuItem()
            analyticsItem.view = UsageAnalyticsMenuView(
                usagePresentation: usagePresentation,
                lifetimePresentation: lifetimePresentation,
                selectedSection: menuAnalyticsSection,
                onSelect: { [weak self] section in
                    guard let self else { return }
                    menuAnalyticsSection = section
                    section.persist(to: defaults)
                }
            )
            menu.addItem(analyticsItem)
        }

        menu.addItem(.separator())
        menu.addItem(actionItem(title: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r"))
        menu.addItem(refreshFrequencyItem())
        menu.addItem(actionItem(title: "Open ChatGPT", action: #selector(openChatGPT), keyEquivalent: "o"))
        menu.addItem(
            actionItem(
                title: "Open Analytics Dashboard…",
                action: #selector(openAnalyticsDashboard),
                keyEquivalent: "d"
            )
        )
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

    private func refreshFrequencyItem() -> NSMenuItem {
        let parent = NSMenuItem(title: "Refresh Frequency", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Refresh Frequency")
        let order: [RefreshFrequency] = [
            .adaptive,
            .manual,
            .oneMinute,
            .twoMinutes,
            .fiveMinutes,
            .fifteenMinutes,
            .thirtyMinutes
        ]
        for frequency in order {
            let item = NSMenuItem(
                title: frequency.displayName,
                action: #selector(setRefreshFrequency),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = NSNumber(value: frequency.rawValue)
            item.state = coordinator.frequency == frequency ? .on : .off
            submenu.addItem(item)
        }
        parent.submenu = submenu
        return parent
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

    @objc private func openAnalyticsDashboard() {
        let controller: AnalyticsWindowController
        if let analyticsWindowController {
            controller = analyticsWindowController
        } else {
            controller = AnalyticsWindowController()
            analyticsWindowController = controller
        }
        controller.show(
            dataset: snapshot?.analyticsDataset,
            errorState: dashboardErrorState,
            profileStats: snapshot?.profileStats,
            profileErrorState: profileDashboardErrorState
        )
    }

    private var dashboardErrorState: AnalyticsDashboardErrorState? {
        analyticsStale || snapshot?.analyticsDataset == nil ? .analyticsUnavailable : nil
    }

    private var profileDashboardErrorState: AnalyticsDashboardErrorState? {
        profileStale || snapshot?.profileStats == nil ? .profileUnavailable : nil
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
