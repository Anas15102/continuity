import SwiftUI

/// Shows recent phone notifications, calls, and SMS on the Mac.
struct NotificationsView: View {
    @EnvironmentObject var notifBridge: NotificationBridge
    @EnvironmentObject var callBridge: CallBridge
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Phone Notifications")
                    .font(.headline)
                Spacer()
                if !notifBridge.recentNotifications.isEmpty {
                    Button("Clear") { notifBridge.clearAll() }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Done") { dismiss() }
                    .padding(.leading, 8)
            }
            .padding()

            Divider()

            if notifBridge.recentNotifications.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "bell.slash")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("No notifications yet")
                        .foregroundStyle(.secondary)
                    Text("Notifications from your phone will appear here.\nMake sure the Continuity app is running on your phone.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List(notifBridge.recentNotifications) { notif in
                    NotificationRow(notif: notif)
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 380, height: 460)
    }
}

struct NotificationRow: View {
    let notif: PhoneNotification

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // App icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                Text(String(notif.app.prefix(1)).uppercased())
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(notif.app)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(notif.time, style: .relative)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                Text(notif.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                if !notif.body.isEmpty {
                    Text(notif.body)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
