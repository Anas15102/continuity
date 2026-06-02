import Foundation
import UserNotifications
import AppKit

/// Receives notifications, calls, and SMS from the Android companion
/// and displays them as native macOS notifications.
/// Also polls via ADB for devices without the companion APK installed.
final class NotificationBridge: ObservableObject {
    static let shared = NotificationBridge()
    private init() {
        requestPermission()
    }

    // MARK: - Published State

    @Published var recentNotifications: [PhoneNotification] = []

    // MARK: - Permission

    private func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            print("[Notifications] Permission granted: \(granted)")
        }
    }

    // MARK: - Show Notification

    func showNotification(app: String, title: String, body: String) {
        let appName = friendlyAppName(app)

        // Add to in-app list
        let notif = PhoneNotification(app: appName, title: title, body: body, time: Date())
        DispatchQueue.main.async {
            self.recentNotifications.insert(notif, at: 0)
            if self.recentNotifications.count > 50 {
                self.recentNotifications = Array(self.recentNotifications.prefix(50))
            }
        }

        // Show macOS notification
        let content = UNMutableNotificationContent()
        content.title = "\(appName): \(title)"
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func showSMS(sender: String, body: String) {
        showNotification(app: "com.android.mms", title: sender, body: body)
    }

    /// Handle messages routed from ClipboardSyncDaemon socket
    func handleSocketMessage(json: [String: String]) {
        switch json["type"] {
        case "notification":
            if let app = json["app"], let title = json["title"], let body = json["body"] {
                showNotification(app: app, title: title, body: body)
            }
        case "sms":
            if let sender = json["sender"], let body = json["body"] {
                showSMS(sender: sender, body: body)
            }
        default:
            break
        }
    }

    func clearAll() {
        DispatchQueue.main.async { self.recentNotifications = [] }
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    // MARK: - ADB Polling Fallback
    // Used when companion APK is not installed.
    // Polls notification shade via ADB dumpsys every 5 seconds.

    private var pollTimer: Timer?

    func startADBPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.pollNotificationsViaADB()
        }
    }

    func stopADBPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private var lastSeenNotifKeys = Set<String>()

    private func pollNotificationsViaADB() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }

            // dumpsys notification gives us active notifications
            let output = ADBBridge.shared.shell("dumpsys notification --noredact 2>/dev/null | grep -A3 'pkg='")
            let lines = output.components(separatedBy: "\n")

            var currentPkg = ""
            var currentTitle = ""
            var currentText = ""

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("pkg=") {
                    // Save previous if complete
                    if !currentPkg.isEmpty && !currentTitle.isEmpty {
                        let key = "\(currentPkg):\(currentTitle)"
                        if !self.lastSeenNotifKeys.contains(key) {
                            self.lastSeenNotifKeys.insert(key)
                            self.showNotification(app: currentPkg, title: currentTitle, body: currentText)
                        }
                    }
                    currentPkg = trimmed.replacingOccurrences(of: "pkg=", with: "")
                        .components(separatedBy: " ").first ?? ""
                    currentTitle = ""
                    currentText = ""
                } else if trimmed.hasPrefix("android.title=") {
                    currentTitle = trimmed.replacingOccurrences(of: "android.title=", with: "")
                } else if trimmed.hasPrefix("android.text=") {
                    currentText = trimmed.replacingOccurrences(of: "android.text=", with: "")
                }
            }
        }
    }

    // MARK: - Helpers

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
            "com.netflix.mediaclient": "Netflix",
            "com.google.android.youtube": "YouTube",
            "com.linkedin.android": "LinkedIn",
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
}
