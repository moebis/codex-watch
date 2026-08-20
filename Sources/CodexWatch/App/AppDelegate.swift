import AppKit

enum AppIdentity {
    static let bundleIdentifier = "com.moebis.codexwatch"
    static let chatGPTCodexBundleIdentifier = "com.openai.codex"
    static let usageAnalyticsURL = URL(
        string: "https://chatgpt.com/codex/cloud/settings/analytics#usage"
    )!

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "development"
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private var wakeObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let controller = MenuBarController(
            refreshFrequency: RefreshFrequency.load(),
            persistRefreshFrequency: { $0.persist() }
        )
        menuBarController = controller
        controller.start()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.menuBarController?.wake()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        wakeObserver = nil
        menuBarController?.stop()
    }
}
