package com.continuity.android

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log

private const val TAG = "MessageReplyHandler"

/**
 * Handles reply commands from Mac.
 * Sends SMS via Android's built-in messaging intent.
 * For WhatsApp/Telegram etc., opens the app with pre-filled message.
 */
object MessageReplyHandler {

    fun send(context: Context, to: String, message: String, app: String) {
        when {
            app.contains("whatsapp", ignoreCase = true) -> sendWhatsApp(context, to, message)
            app.contains("telegram", ignoreCase = true) -> sendTelegram(context, to, message)
            else -> sendSMS(context, to, message)
        }
    }

    fun sendSMS(context: Context, to: String, message: String) {
        try {
            // Try direct SMS API first (no UI needed)
            val smsManager = context.getSystemService(android.telephony.SmsManager::class.java)
            smsManager?.sendTextMessage(to, null, message, null, null)
            Log.i(TAG, "SMS sent to $to")
        } catch (e: Exception) {
            Log.w(TAG, "Direct SMS failed, using intent: ${e.message}")
            // Fallback: open messaging app with pre-filled text
            val intent = Intent(Intent.ACTION_SENDTO).apply {
                data = Uri.parse("smsto:$to")
                putExtra("sms_body", message)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            context.startActivity(intent)
        }
    }

    private fun sendWhatsApp(context: Context, to: String, message: String) {
        try {
            val intent = Intent(Intent.ACTION_VIEW).apply {
                data = Uri.parse("https://wa.me/$to?text=${Uri.encode(message)}")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            context.startActivity(intent)
        } catch (e: Exception) {
            Log.w(TAG, "WhatsApp intent failed: ${e.message}")
            sendSMS(context, to, message)
        }
    }

    private fun sendTelegram(context: Context, to: String, message: String) {
        try {
            val intent = Intent(Intent.ACTION_VIEW).apply {
                data = Uri.parse("tg://msg?to=$to&text=${Uri.encode(message)}")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            context.startActivity(intent)
        } catch (e: Exception) {
            Log.w(TAG, "Telegram intent failed: ${e.message}")
        }
    }
}
