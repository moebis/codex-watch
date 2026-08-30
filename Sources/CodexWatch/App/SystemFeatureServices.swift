import Foundation
import ServiceManagement
import UserNotifications

protocol QuotaNotificationDelivering: Sendable {
    func requestAuthorization() async -> Bool
    func deliver(_ decision: QuotaNotificationDecision) async throws
}

struct UnavailableQuotaNotificationDelivery: QuotaNotificationDelivering {
    func requestAuthorization() async -> Bool { false }
    func deliver(_ decision: QuotaNotificationDecision) async throws {}
}

actor QuotaNotificationController {
    private let delivery: any QuotaNotificationDelivering
    private var policy = QuotaNotificationPolicy()
    private var isEnabled = false

    init(delivery: any QuotaNotificationDelivering = SystemQuotaNotificationDelivery()) {
        self.delivery = delivery
    }

    func requestEnable() async -> Bool {
        let granted = await delivery.requestAuthorization()
        isEnabled = granted
        return granted
    }

    func disable() {
        isEnabled = false
    }

    func consider(
        remainingPercent: Double?,
        isFresh: Bool,
        windowResetAt: Date? = nil
    ) async {
        guard isEnabled,
              let decision = policy.consume(
                  remainingPercent: remainingPercent,
                  isFresh: isFresh,
                  windowResetAt: windowResetAt
              ) else { return }
        try? await delivery.deliver(decision)
    }
}

struct SystemQuotaNotificationDelivery: QuotaNotificationDelivering, @unchecked Sendable {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    func deliver(_ decision: QuotaNotificationDecision) async throws {
        let content = UNMutableNotificationContent()
        content.title = decision.title
        content.body = decision.body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: decision.identifier,
            content: content,
            trigger: nil
        )
        try await center.add(request)
    }
}

@MainActor
protocol LaunchAtLoginServicing: AnyObject {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

enum SystemFeatureServiceError: Error {
    case unavailable
}

@MainActor
final class UnavailableLaunchAtLoginService: LaunchAtLoginServicing {
    var isEnabled: Bool { false }
    func setEnabled(_ enabled: Bool) throws {
        throw SystemFeatureServiceError.unavailable
    }
}

@MainActor
final class MainAppLaunchAtLoginService: LaunchAtLoginServicing {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else if SMAppService.mainApp.status != .notRegistered {
            try SMAppService.mainApp.unregister()
        }
    }
}

@MainActor
final class LaunchAtLoginSetting {
    private let service: any LaunchAtLoginServicing

    init(service: any LaunchAtLoginServicing) {
        self.service = service
    }

    convenience init() {
        self.init(service: MainAppLaunchAtLoginService())
    }

    var isEnabled: Bool {
        service.isEnabled
    }

    func setEnabled(_ enabled: Bool) throws {
        try service.setEnabled(enabled)
    }
}
