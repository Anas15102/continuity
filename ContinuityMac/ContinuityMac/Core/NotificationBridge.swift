import Foundation
import UserNotifications
import AppKit

/// Receives notifications and SMS from the Android companion.
/// Shows native macOS notifications with inline reply support.
final class NotificationBridge: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationBridge()
    override private init() {
        super.init()
        requestPermission()
    }

    // MARK: - Published State

    @Published var recentNotifications: [PhoneNotification] = []

    // Reply action identifier
    static let replyActionID    = "CONTINUITY_REPLY"
    static let dismissActionID  = "CONTINUITY_DISMISS"
    static let categoryID       = "CONTINUITY_MESSAGE"

    // MARK: - Permission + Setup

    private func requestPermission() {
        let replyAction = UNTextInputNotificationAction(
            identifier: Self.replyActionID,
            title: "Reply",
            options: [],
            textInputButtonTitle: "Send",
            textInputPlaceholder: "Type a reply..."
        )
        let dismissAction = UNNotificationAction(
            identifier: Self.dismissActionID,
            title: "Dismiss",
            options: [.destructive]
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryID,
            actions: [replyAction, dismissAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        UNUserNotificationCenter.current().setNotificationCategories([category])
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { granted, _ in
            print("[Notifications] Permission: \(granted)")
        }
    }

    // MARK: - Show Notification

    func showNotification(app: String, title: String, body: String, replyTo: String? = nil) {
        let appName = friendlyAppName(app)

        // Save to in-app list
        let notif = PhoneNotification(app: appName, title: title, body: body, time: Date(), replyTarget: replyTo)
        DispatchQueue.main.async {
            self.recentNotifications.insert(notif, at: 0)
            if self.recentNotifications.count > 50 {
                self.recentNotifications = Array(self.recentNotifications.prefix(50))
            }
        }

        // Build macOS notification
        let content = UNMutableNotificationContent()
        content.title = appName
        content.subtitle = title
        content.body = body
        content.sound = .default

        // Add reply button for messaging apps
        if replyTo != nil || isMessagingApp(app) {
            content.categoryIdentifier = Self.categoryID
            // Store reply context
            content.userInfo = [
                "app": app,
                "sender": title,
                "replyTo": replyTo ?? title
            ]
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func showSMS(sender: String, body: String) {
        showNotification(app: "com.android.mms", title: sender, body: body, replyTo: sender)
    }

    // MARK: - UNUserNotificationCenterDelegate (reply handler)

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let app = userInfo["app"] as? String ?? ""
        let replyTo = userInfo["replyTo"] as? String ?? ""

        switch response.actionIdentifier {
        case Self.replyActionID:
            if let textResponse = response as? UNTextInputNotificationResponse {
                let replyText = textResponse.userText
                guard !replyText.isEmpty else { break }
                sendReply(to: replyTo, message: replyText, app: app)
            }
        default:
            break
        }
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    // MARK: - Send Reply to Android

    private func sendReply(to recipient: String, message: String, app: String) {
        print("[NotificationBridge] Replying to \(recipient): \(message.prefix(40))")

        // Send over TCP socket to Android
        let payload: [String: Any] = [
            "type": "reply",
            "to": recipient,
            "message": message,
            "app": app
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        ClipboardSyncDaemon.shared.sendRawPacket(data)
    }

    // MARK: - Socket Message Handler

    func handleSocketMessage(json: [String: Any]) {
        guard let type = json["type"] as? String else { return }
        switch type {
        case "notification":
            if let app = json["app"] as? String,
               let title = json["title"] as? String,
               let body = json["body"] as? String {
                showNotification(app: app, title: title, body: body)
            }
        case "sms":
            if let sender = json["sender"] as? String,
               let body = json["body"] as? String {
                showSMS(sender: sender, body: body)
            }
        default:
            break
        }
    }

    // Legacy string-dict overload
    func handleSocketMessage(json: [String: String]) {
        let anyJson = json.reduce(into: [String: Any]()) { $0[$1.key] = $1.value }
        handleSocketMessage(json: anyJson)
    }

    func clearAll() {
        DispatchQueue.main.async { self.recentNotifications = [] }
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    // MARK: - ADB Polling Fallback

    private var pollTimer: Timer?
    private var lastSeenNotifKeys = Set<String>()

    func startADBPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.pollNotificationsViaADB()
        }
    }

    func stopADBPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func pollNotificationsViaADB() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }
            let output = ADBBridge.shared.shell("dumpsys notification --noredact 2>/dev/null | grep -A3 'pkg='")
            let lines = output.components(separatedBy: "\n")
            var pkg = "", title = "", text = ""
            for line in lines {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("pkg=") {
                    if !pkg.isEmpty && !title.isEmpty {
                        let key = "\(pkg):\(title)"
                        if !self.lastSeenNotifKeys.contains(key) {
                            self.lastSeenNotifKeys.insert(key)
                            self.showNotification(app: pkg, title: title, body: text)
                        }
                    }
                    pkg = t.replacingOccurrences(of: "pkg=", with: "").components(separatedBy: " ").first ?? ""
                    title = ""; text = ""
                } else if t.hasPrefix("android.title=") {
                    title = t.replacingOccurrences(of: "android.title=", with: "")
                } else if t.hasPrefix("android.text=") {
                    text = t.replacingOccurrences(of: "android.text=", with: "")
                }
            }
        }
    }

    // MARK: - Helpers

    private func isMessagingApp(_ packageName: String) -> Bool {
        let messaging = [
            "com.whatsapp", "com.whatsapp.w4b", "com.google.android.apps.messaging",
            "com.android.mms", "com.facebook.orca", "com.telegram.messenger",
            "org.thoughtcrime.securesms", "com.instagram.android", "com.snapchat.android"
        ]
        return messaging.contains(packageName)
    }

    private func friendlyAppName(_ packageName: String) -> String {
        let known: [String: String] = [
            "com.whatsapp": "WhatsApp",
            "com.whatsapp.w4b": "WhatsApp Business",
            "com.instagram.android": "Instagram",
            "com.snapchat.android": "Snapchat",
            "com.google.android.gm": "Gmail",
            "com.google.android.apps.messaging": "Messages",
            "com.android.mms": "Messages",
            "com.android.dialer": "Phone",
            "com.google.android.dialer": "Phone",
            "com.twitter.android": "Twitter/X",
            "com.facebook.katana": "Facebook",
            "com.facebook.orca": "Messenger",
            "com.spotify.music": "Spotify",
            "com.telegram.messenger": "Telegram",
            "org.thoughtcrime.securesms": "Signal",
        ]
        return known[packageName]
            ?? packageName.components(separatedBy: ".").last?.capitalized
            ?? packageName
    }
}

// MARK: - Model

struct PhoneNotification: Identifiable {
    let id = UUID()
    let app: String
    let title: String
    let body: String
    let time: Date
    var replyTarget: String?
}
