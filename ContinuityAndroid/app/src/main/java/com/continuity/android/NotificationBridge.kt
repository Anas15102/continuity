package com.continuity.android

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.telephony.TelephonyManager
import android.content.Context

/**
 * Listens for all Android notifications and forwards them to the Mac.
 * Also detects incoming calls via notification (works without phone permission).
 */
class NotificationBridge : NotificationListenerService() {

    // Packages to skip (system noise)
    private val skipPackages = setOf(
        "android", "com.android.systemui", "com.android.launcher3",
        "com.google.android.gms", "com.android.settings"
    )

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        if (sbn.packageName in skipPackages) return
        if (!ConnectionManager.isConnected()) return

        val extras = sbn.notification.extras
        val title = extras.getString("android.title") ?: ""
        val text = extras.getCharSequence("android.text")?.toString() ?: ""

        if (title.isEmpty() && text.isEmpty()) return

        // Detect incoming call notifications
        if (sbn.packageName == "com.android.dialer" ||
            sbn.packageName == "com.google.android.dialer" ||
            title.contains("Incoming call", ignoreCase = true)) {
            ConnectionManager.sendIncomingCall(caller = title, number = text)
            return
        }

        // Detect SMS from Messages app
        if (sbn.packageName == "com.google.android.apps.messaging" ||
            sbn.packageName == "com.android.mms") {
            ConnectionManager.sendSMS(sender = title, body = text)
            return
        }

        // All other notifications
        ConnectionManager.sendNotification(
            app = sbn.packageName,
            title = title,
            body = text
        )
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        // If a call notification is removed, the call ended
        if (sbn.packageName == "com.android.dialer" ||
            sbn.packageName == "com.google.android.dialer") {
            ConnectionManager.sendCallEnded()
        }
    }
}
