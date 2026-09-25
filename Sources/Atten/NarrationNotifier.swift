import AppKit
import Foundation
import UserNotifications

/// Tells someone who has gone to another app that a book is ready. Someone
/// still in Atten already sees it on the shelf, so nothing is sent then.
///
/// Permission is asked for the first time there is something to say, never
/// at launch.
@MainActor
final class NarrationNotifier {
    var isAppFrontmost: () -> Bool = { NSApp?.isActive ?? true }
    var authorize: () async -> Bool = { await SystemNotifications.shared.authorize() }
    var deliver: (_ title: String, _ bookID: UUID) -> Void = { SystemNotifications.shared.deliver(title: $0, bookID: $1) }

    @discardableResult
    func narrationFinished(bookID: UUID, title: String) -> Task<Void, Never>? {
        guard !isAppFrontmost() else { return nil }
        return Task {
            guard await authorize() else { return }
            deliver(title, bookID)
        }
    }
}

/// `UNUserNotificationCenter`, touched only once there is a notification to
/// send: a binary run outside an app bundle (`swift run`, the tests) has no
/// notification center at all.
@MainActor
final class SystemNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = SystemNotifications()

    /// Opens the book a clicked notification was about.
    var open: (UUID) -> Void = { _ in }

    private var center: UNUserNotificationCenter? {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return nil }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        return center
    }

    func authorize() async -> Bool {
        guard let center else { return false }
        return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func deliver(title: String, bookID: UUID) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = "Ready to listen"
        content.sound = .default
        content.userInfo = ["bookID": bookID.uuidString]
        center?.add(UNNotificationRequest(identifier: bookID.uuidString, content: content, trigger: nil))
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let raw = response.notification.request.content.userInfo["bookID"] as? String,
              let bookID = UUID(uuidString: raw) else { return }
        await MainActor.run {
            NSApp?.activate(ignoringOtherApps: true)
            open(bookID)
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
