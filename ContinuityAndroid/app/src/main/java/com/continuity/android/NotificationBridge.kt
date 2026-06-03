package com.continuity.android

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import org.json.JSONObject

private const val TAG = "NotificationBridge"

/**
 * Listens for all Android notifications and forwards them to the Mac.
 *
 * - Messaging apps (WhatsApp, SMS, Telegram etc.) → shown on Mac with Reply button
 * - Incoming calls → call banner on Mac with Answer/Decline
 * - Call answered/ended on phone → updates Mac banner immediately
 * - All other notifications → standard Mac notification
 */
class NotificationBridge : NotificationListenerService() {

    private val skipPackages = setOf(
        "android", "com.android.systemui", "com.android.launcher3",
        "com.google.android.gms", "com.android.settings",
        "com.continuity.android"  // skip our own notifications
    )

    private val messagingPackages = setOf(
        "com.whatsapp", "com.whatsapp.w4b",
        "com.google.android.apps.messaging", "com.android.mms",
        "com.facebook.orca", "com.telegram.messenger",
        "org.thoughtcrime.securesms", "com.instagram.android",
        "com.snapchat.android", "com.discord"
    )

    private val dialerPackages = setOf(
        "com.android.dialer", "com.google.android.dialer",
        "com.samsung.android.incallui"
    )

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        if (sbn.packageName in skipPackages) return
        if (!ConnectionManager.isConnected()) return

        val extras = sbn.notification.extras
        val title = extras.getString("android.title") ?: ""
        val text = extras.getCharSequence("android.text")?.toString() ?: ""
        if (title.isEmpty() && text.isEmpty()) return

        val pkg = sbn.packageName

        when {
            // Incoming call notification
            pkg in dialerPackages || title.contains("Incoming call", ignoreCase = true) -> {
                Log.d(TAG, "Incoming call: $title / $text")
                ConnectionManager.sendIncomingCall(caller = title, number = text)
            }

            // Call answered on phone — notify Mac to update its banner
            title.contains("active call", ignoreCase = true) ||
            title.contains("on a call", ignoreCase = true) -> {
                ConnectionManager.sendJSON(JSONObject().put("type", "call_answered"))
            }

            // SMS
            pkg == "com.google.android.apps.messaging" || pkg == "com.android.mms" -> {
                Log.d(TAG, "SMS from $title")
                ConnectionManager.sendSMS(sender = title, body = text)
            }

            // Messaging apps — send with app context for smart reply routing
            pkg in messagingPackages -> {
                Log.d(TAG, "Message from $pkg: $title")
                ConnectionManager.sendJSON(
                    JSONObject()
                        .put("type", "notification")
                        .put("app", pkg)
                        .put("title", title)
                        .put("body", text)
                        .put("replyable", true)
                )
            }

            // Everything else
            else -> {
                ConnectionManager.sendNotification(app = pkg, title = title, body = text)
            }
        }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        val pkg = sbn.packageName
        // Call ended or dismissed on phone
        if (pkg in dialerPackages) {
            Log.d(TAG, "Call ended (notification removed)")
            ConnectionManager.sendCallEnded()
        }
    }
}
