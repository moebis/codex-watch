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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let controller = MenuBarController()
        menuBarController = controller
        controller.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        menuBarController?.stop()
    }
}
