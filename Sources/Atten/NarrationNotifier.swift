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

    /// Opens the book a clicked notification was about. Nil until the
    /// shelf has loaded; a click that arrives before then — the one that
    /// launched Atten — waits for it.
    var open: ((UUID) -> Void)? {
        didSet {
            guard let open, let pending = pendingBookID else { return }
            pendingBookID = nil
            open(pending)
        }
    }
    private(set) var pendingBookID: UUID?

    private nonisolated var center: UNUserNotificationCenter? {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return nil }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        return center
    }

    /// Nonisolated, so the center is fetched and asked in one context and
    /// never sent across the main actor's boundary.
    nonisolated func authorize() async -> Bool {
        guard let center else { return false }
        return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Called at launch. A click on a notification from an earlier run is
    /// handed to the center's delegate as Atten starts, so the delegate has
    /// to be in place before launching finishes or the click is lost.
    nonisolated func startListening() {
        _ = center
    }

    func deliver(title: String, bookID: UUID) {
        center?.add(UNNotificationRequest(identifier: bookID.uuidString, content: Self.content(title: title, bookID: bookID), trigger: nil))
    }

    /// The book travels in `userInfo`, which is all a click from an earlier
    /// run still has to go on.
    static func content(title: String, bookID: UUID) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = "Ready to listen"
        content.sound = .default
        content.userInfo = ["bookID": bookID.uuidString]
        return content
    }

    /// Opens the book a clicked notification names, now or once the shelf
    /// has loaded.
    func route(_ userInfo: [AnyHashable: Any]) {
        guard let raw = userInfo["bookID"] as? String, let bookID = UUID(uuidString: raw) else { return }
        if let open { open(bookID) } else { pendingBookID = bookID }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        // Only the book's id string crosses to the main actor.
        guard let raw = response.notification.request.content.userInfo["bookID"] as? String else { return }
        await MainActor.run {
            NSApp?.activate(ignoringOtherApps: true)
            route(["bookID": raw])
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
