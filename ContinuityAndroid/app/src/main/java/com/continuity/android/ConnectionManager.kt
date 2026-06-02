package com.continuity.android

import android.util.Log
import java.io.InputStream
import java.io.OutputStream
import java.net.ServerSocket
import java.net.Socket
import java.nio.ByteBuffer
import kotlin.concurrent.thread
import org.json.JSONObject

private const val TAG = "ConnectionManager"

/**
 * Android-side TCP server on port 9876.
 * The Mac connects TO us — we just listen.
 *
 * All subsystems call sendJSON() to push data to the Mac.
 * Incoming messages from Mac are dispatched to registered handlers.
 */
object ConnectionManager {

    const val PORT = 9876

    private var serverSocket: ServerSocket? = null
    private var clientSocket: Socket? = null
    private var outputStream: OutputStream? = null
    private var isRunning = false

    // Handlers registered by subsystems
    var onClipboardReceived: ((String) -> Unit)? = null
    var onMacConnected: (() -> Unit)? = null
    var onMacDisconnected: (() -> Unit)? = null

    fun isConnected() = clientSocket?.isConnected == true && clientSocket?.isClosed == false

    // MARK: - Start / Stop

    fun start() {
        if (isRunning) return
        isRunning = true
        thread(name = "ContinuityServer") {
            try {
                serverSocket = ServerSocket(PORT)
                Log.i(TAG, "TCP server listening on :$PORT")
                while (isRunning) {
                    val client = serverSocket?.accept() ?: break
                    Log.i(TAG, "Mac connected from ${client.inetAddress.hostAddress}")
                    handleClient(client)
                }
            } catch (e: Exception) {
                if (isRunning) Log.e(TAG, "Server error: ${e.message}")
            }
        }
    }

    fun stop() {
        isRunning = false
        clientSocket?.close()
        serverSocket?.close()
        clientSocket = null
        outputStream = null
        onMacDisconnected?.invoke()
        Log.i(TAG, "Server stopped.")
    }

    // MARK: - Client Handler

    private fun handleClient(socket: Socket) {
        // Only allow one Mac connection at a time
        clientSocket?.close()
        clientSocket = socket
        outputStream = socket.getOutputStream()
        onMacConnected?.invoke()

        thread(name = "ContinuityReceiver") {
            try {
                val input: InputStream = socket.getInputStream()
                while (isRunning && !socket.isClosed) {
                    // Read 4-byte big-endian length prefix
                    val lenBuf = ByteArray(4)
                    var totalRead = 0
                    while (totalRead < 4) {
                        val n = input.read(lenBuf, totalRead, 4 - totalRead)
                        if (n < 0) throw Exception("Stream closed")
                        totalRead += n
                    }
                    val length = ByteBuffer.wrap(lenBuf).int
                    if (length <= 0 || length > 4_000_000) continue

                    val payload = ByteArray(length)
                    var read = 0
                    while (read < length) {
                        val n = input.read(payload, read, length - read)
                        if (n < 0) throw Exception("Stream closed mid-payload")
                        read += n
                    }

                    dispatch(JSONObject(String(payload, Charsets.UTF_8)))
                }
            } catch (e: Exception) {
                Log.w(TAG, "Client disconnected: ${e.message}")
            } finally {
                clientSocket = null
                outputStream = null
                onMacDisconnected?.invoke()
            }
        }
    }

    // MARK: - Incoming Message Dispatch

    private fun dispatch(json: JSONObject) {
        when (json.optString("type")) {
            "clipboard" -> {
                val text = json.optString("text")
                if (text.isNotEmpty()) {
                    Log.d(TAG, "Mac→Android clipboard: ${text.take(40)}")
                    onClipboardReceived?.invoke(text)
                }
            }
            "ping" -> sendJSON(JSONObject().put("type", "pong"))
            else -> Log.d(TAG, "Unknown message type: ${json.optString("type")}")
        }
    }

    // MARK: - Send to Mac

    fun sendJSON(payload: JSONObject) {
        val out = outputStream ?: return
        thread(name = "MacSender") {
            try {
                val data = payload.toString().toByteArray(Charsets.UTF_8)
                val lenBytes = ByteBuffer.allocate(4).putInt(data.size).array()
                synchronized(out) {
                    out.write(lenBytes)
                    out.write(data)
                    out.flush()
                }
            } catch (e: Exception) {
                Log.w(TAG, "Send error: ${e.message}")
                clientSocket = null
                outputStream = null
                onMacDisconnected?.invoke()
            }
        }
    }

    fun sendClipboard(text: String) = sendJSON(
        JSONObject().put("type", "clipboard").put("text", text)
    )

    fun sendNotification(app: String, title: String, body: String) = sendJSON(
        JSONObject().put("type", "notification").put("app", app).put("title", title).put("body", body)
    )

    fun sendIncomingCall(caller: String, number: String) = sendJSON(
        JSONObject().put("type", "call_incoming").put("caller", caller).put("number", number)
    )

    fun sendCallEnded() = sendJSON(JSONObject().put("type", "call_ended"))

    fun sendSMS(sender: String, body: String) = sendJSON(
        JSONObject().put("type", "sms").put("sender", sender).put("body", body)
    )
}
