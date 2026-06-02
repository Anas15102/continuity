package com.continuity.android

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log

private const val TAG = "ClipboardSync"

/**
 * Two-way clipboard sync.
 *
 * Android → Mac: ClipboardManager.OnPrimaryClipChangedListener fires when
 *   the user copies something. Works from a foreground service on Android 10+.
 *
 * Mac → Android: ConnectionManager.onClipboardReceived callback writes to
 *   the Android clipboard on the main thread.
 */
class ClipboardSyncReceiver(private val context: Context) {

    private val clipboardManager by lazy {
        context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var lastContent = ""

    private val clipListener = ClipboardManager.OnPrimaryClipChangedListener {
        val text = clipboardManager.primaryClip
            ?.getItemAt(0)?.text?.toString() ?: return@OnPrimaryClipChangedListener

        if (text.isNotEmpty() && text != lastContent) {
            lastContent = text
            Log.d(TAG, "Android→Mac: ${text.take(40)}")
            ConnectionManager.sendClipboard(text)
        }
    }

    fun start() {
        // Register listener on main thread (required by ClipboardManager)
        mainHandler.post {
            clipboardManager.addPrimaryClipChangedListener(clipListener)
            Log.i(TAG, "Clipboard listener registered.")
        }

        // Handle clipboard coming in from Mac
        ConnectionManager.onClipboardReceived = { text ->
            if (text != lastContent) {
                lastContent = text
                mainHandler.post {
                    try {
                        val clip = ClipData.newPlainText("Continuity", text)
                        clipboardManager.setPrimaryClip(clip)
                        Log.d(TAG, "Mac→Android written: ${text.take(40)}")
                    } catch (e: Exception) {
                        Log.w(TAG, "Failed to write clipboard: ${e.message}")
                    }
                }
            }
        }
    }

    fun stop() {
        mainHandler.post {
            clipboardManager.removePrimaryClipChangedListener(clipListener)
        }
        ConnectionManager.onClipboardReceived = null
        Log.i(TAG, "Clipboard listener removed.")
    }
}
