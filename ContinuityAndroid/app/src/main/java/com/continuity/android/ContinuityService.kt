package com.continuity.android

import android.app.*
import android.content.Intent
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat

private const val TAG = "ContinuityService"

/**
 * Foreground service that keeps all Continuity features alive in the background.
 *
 * Start order:
 *   1. ConnectionManager.start()  — TCP server on port 9876, Mac connects to us
 *   2. MdnsAdvertiser.start()     — Advertise on local network so Mac finds us
 *   3. ClipboardSyncReceiver.start() — Two-way clipboard via the TCP connection
 */
class ContinuityService : Service() {

    private val CHANNEL_ID = "continuity_service"
    private val NOTIFICATION_ID = 1001

    private lateinit var mdnsAdvertiser: MdnsAdvertiser
    private lateinit var clipboardReceiver: ClipboardSyncReceiver

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        mdnsAdvertiser = MdnsAdvertiser(this)
        clipboardReceiver = ClipboardSyncReceiver(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            Log.i(TAG, "Stop action received.")
            stopSelf()
            return START_NOT_STICKY
        }

        startForeground(NOTIFICATION_ID, buildNotification("Waiting for Mac…"))

        // Start TCP server first, then advertise, then clipboard
        ConnectionManager.start()
        mdnsAdvertiser.start()
        clipboardReceiver.start()

        // Update notification when Mac connects/disconnects
        ConnectionManager.onMacConnected = {
            updateNotification("Connected to Mac — clipboard sync active")
            Log.i(TAG, "Mac connected.")
        }
        ConnectionManager.onMacDisconnected = {
            updateNotification("Waiting for Mac…")
            Log.i(TAG, "Mac disconnected.")
        }

        Log.i(TAG, "Service started. Listening on port ${ConnectionManager.PORT}")
        return START_STICKY
    }

    override fun onDestroy() {
        clipboardReceiver.stop()
        mdnsAdvertiser.stop()
        ConnectionManager.stop()
        super.onDestroy()
        Log.i(TAG, "Service destroyed.")
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // MARK: - Notification

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Continuity Service",
            NotificationManager.IMPORTANCE_LOW
        ).apply { description = "Keeps Continuity connected to your Mac" }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private fun buildNotification(status: String): Notification {
        val stopIntent = Intent(this, ContinuityService::class.java).apply { action = ACTION_STOP }
        val stopPi = PendingIntent.getService(
            this, 0, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val openIntent = Intent(this, MainActivity::class.java)
        val openPi = PendingIntent.getActivity(
            this, 0, openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Continuity")
            .setContentText(status)
            .setSmallIcon(android.R.drawable.stat_sys_data_bluetooth)
            .setOngoing(true)
            .setContentIntent(openPi)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Stop", stopPi)
            .build()
    }

    private fun updateNotification(status: String) {
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID, buildNotification(status))
    }

    companion object {
        const val ACTION_STOP = "com.continuity.android.ACTION_STOP"
    }
}
