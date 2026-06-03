package com.continuity.android

import android.util.Log

private const val TAG = "CallActionHandler"

/**
 * Handles call control commands from Mac (answer, decline, hangup).
 * Uses ADB keyevents via shell — works on all Android versions.
 *
 * KEYCODE_CALL = 5    → Answer
 * KEYCODE_ENDCALL = 6 → Decline / Hangup
 */
object CallActionHandler {

    fun handle(action: String) {
        Log.i(TAG, "Call action: $action")
        when (action) {
            "answer"  -> answerCall()
            "decline" -> endCall()
            "hangup"  -> endCall()
        }
    }

    private fun answerCall() {
        try {
            // Android 8+ supports telecom service
            Runtime.getRuntime().exec(arrayOf("input", "keyevent", "5"))
            Log.i(TAG, "Answer keyevent sent")
        } catch (e: Exception) {
            Log.w(TAG, "Answer failed: ${e.message}")
        }
        // Also send via ConnectionManager to notify Mac the call was answered
        ConnectionManager.sendJSON(
            org.json.JSONObject().put("type", "call_answered")
        )
    }

    private fun endCall() {
        try {
            Runtime.getRuntime().exec(arrayOf("input", "keyevent", "6"))
            Log.i(TAG, "Endcall keyevent sent")
        } catch (e: Exception) {
            Log.w(TAG, "End call failed: ${e.message}")
        }
        ConnectionManager.sendJSON(
            org.json.JSONObject().put("type", "call_ended")
        )
    }
}
