import Foundation
import UserNotifications

/// Tells the person through macOS notifications when a job's preview has something new, and opens its card when they
/// click one. macOS asks for permission once a job is on. Without it everything else still works: Jobs and the chat say
/// notifications are off. The notification center exists only for an app bundle; anywhere else (tests, `swift run`)
/// touching it crashes, so there notifications go to the log.
@MainActor
final class JobNotifier: NSObject, ObservableObject {
    /// Why notifications won't show, in plain words; nil when they will (or nobody has been asked yet).
    @Published private(set) var offReason: String?
    /// A job's notification was clicked (`post(job:title:body:)`): the job.
    var onOpenJob: ((UUID) -> Void)?
    private var asked = false

    static var available: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }

    private var center: UNUserNotificationCenter? { Self.available ? UNUserNotificationCenter.current() : nil }

    /// Set up at launch, so a click on a notification reaches the app.
    func activate() {
        center?.delegate = self
    }

    /// Asks macOS once whether Noteling may notify; it only asks the person if they haven't answered before.
    func requestPermission() {
        guard let center else { return }
        guard !asked else { return }
        asked = true
        Task {
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                Log.info("jobs: notifications \(granted ? "allowed" : "not allowed")")
            } catch {
                Log.info("jobs: couldn't ask for notifications: \(error.localizedDescription)")
            }
            await refresh()
        }
    }

    func refresh() async {
        offReason = await reason()
    }

    /// The chat's word on notifications: "on", or why not and how to turn them on.
    func line() async -> String {
        await refresh()
        return offReason.map { "off: \($0)" } ?? "on"
    }

    private func reason() async -> String? {
        guard let center else { return "Notifications need Noteling to run as an app." }
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .denied:
            return "Notifications are off for Noteling. Turn them on in System Settings → Notifications → Noteling."
        case .notDetermined:
            return asked ? "Noteling is waiting for you to allow notifications." : nil
        default:
            return settings.alertSetting == .disabled
                ? "Noteling's alerts are turned off in System Settings → Notifications → Noteling." : nil
        }
    }

    /// That a job's preview has something new: one per job, a newer one replacing it in Notification Center.
    func post(job: UUID, title: String, body: String) {
        guard let center else {
            Log.info("jobs: not shown as a notification: Noteling isn't running as an app")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = job.uuidString
        content.userInfo = ["job": job.uuidString]
        center.add(UNNotificationRequest(identifier: "job-\(job.uuidString)", content: content, trigger: nil)) { error in
            if let error { Log.info("jobs: couldn't show a notification: \(error.localizedDescription)") }
        }
    }
}

extension JobNotifier: UNUserNotificationCenterDelegate {
    /// Shown even while Noteling is the app in front.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let job = (response.notification.request.content.userInfo["job"] as? String).flatMap(UUID.init(uuidString:))
        let clicked = response.actionIdentifier == UNNotificationDefaultActionIdentifier
        Task { @MainActor in
            if clicked, let job { self.onOpenJob?(job) }
            completionHandler()
        }
    }
}
