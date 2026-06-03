package com.continuity.android

import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.InputStream
import java.io.OutputStream
import java.nio.ByteBuffer
import javax.net.ssl.SSLSocket
import kotlin.concurrent.thread

private const val TAG = "ConnectionManager"
private const val PREFS_NAME = "continuity_pairing"
private const val PREFS_PAIRED_MACS = "paired_macs"

/**
 * Android-side TLS TCP server on port 9876.
 *
 * Upgrade features:
 *  1. TLS encryption — all traffic encrypted with self-signed certs
 *  2. Identity exchange — both sides announce capabilities on connect
 *  3. Pairing confirmation — Mac must be approved by user on first connect
 */
object ConnectionManager {

    const val PORT = 9876

    // Capabilities this Android device supports
    val CAPABILITIES = listOf(
        "clipboard", "notification", "call", "sms", "file_transfer", "ping"
    )

    private var serverSocket: javax.net.ssl.SSLServerSocket? = null
    private var clientSocket: SSLSocket? = null
    private var outputStream: OutputStream? = null
    private var isRunning = false
    private var prefs: SharedPreferences? = null

    // Callbacks
    var onClipboardReceived: ((String) -> Unit)? = null
    var onMacConnected: (() -> Unit)? = null
    var onMacDisconnected: (() -> Unit)? = null
    var onPairingRequest: ((macName: String, macId: String, accept: () -> Unit, reject: () -> Unit) -> Unit)? = null

    // Connected Mac identity
    var connectedMacName: String = ""
        private set
    var connectedMacId: String = ""
        private set
    var connectedMacCapabilities: List<String> = emptyList()
        private set

    fun isConnected() = clientSocket?.isConnected == true && clientSocket?.isClosed == false

    // MARK: - Init

    fun init(context: Context) {
        prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        TLSManager.init(context)
        Log.i(TAG, "ConnectionManager initialized.")
    }

    // MARK: - Start / Stop

    fun start() {
        if (isRunning) return
        isRunning = true
        thread(name = "ContinuityServer") {
            try {
                serverSocket = TLSManager.serverSocketFactory()
                    .createServerSocket(PORT) as javax.net.ssl.SSLServerSocket
                serverSocket?.needClientAuth = false
                Log.i(TAG, "TLS server listening on :$PORT")

                while (isRunning) {
                    val client = serverSocket?.accept() as? SSLSocket ?: break
                    Log.i(TAG, "Mac connecting from ${client.inetAddress.hostAddress}")
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

    private fun handleClient(socket: SSLSocket) {
        // Kick existing connection
        clientSocket?.close()

        try {
            socket.startHandshake()
        } catch (e: Exception) {
            Log.w(TAG, "TLS handshake failed: ${e.message}")
            socket.close()
            return
        }

        clientSocket = socket
        outputStream = socket.getOutputStream()

        thread(name = "ContinuityReceiver") {
            try {
                val input: InputStream = socket.getInputStream()

                // Step 1: Send our identity first
                sendIdentity()

                // Step 2: Read Mac's identity
                val identityPacket = readPacket(input) ?: throw Exception("No identity received")
                if (!handleIdentity(identityPacket, socket)) {
                    Log.w(TAG, "Identity/pairing rejected.")
                    socket.close()
                    clientSocket = null
                    outputStream = null
                    return@thread
                }

                // Fully connected
                onMacConnected?.invoke()

                // Step 3: Normal message loop
                while (isRunning && !socket.isClosed) {
                    val packet = readPacket(input) ?: break
                    dispatch(packet)
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

    // MARK: - Identity Exchange

    private fun sendIdentity() {
        val identity = JSONObject().apply {
            put("type", "identity")
            put("deviceName", Build.MODEL)
            put("deviceId", getDeviceId())
            put("deviceType", "phone")
            put("appVersion", "1.0.0")
            put("capabilities", JSONArray(CAPABILITIES))
        }
        sendJSONDirect(identity)
        Log.i(TAG, "Sent identity: ${Build.MODEL}")
    }

    private fun handleIdentity(json: JSONObject, socket: SSLSocket): Boolean {
        if (json.optString("type") != "identity") {
            Log.w(TAG, "Expected identity packet, got: ${json.optString("type")}")
            return false
        }

        val macName = json.optString("deviceName", "Unknown Mac")
        val macId = json.optString("deviceId", "")
        val caps = json.optJSONArray("capabilities")
        val capList = (0 until (caps?.length() ?: 0)).map { caps!!.getString(it) }

        connectedMacName = macName
        connectedMacId = macId
        connectedMacCapabilities = capList

        Log.i(TAG, "Mac identity: $macName, caps: $capList")

        // Check if already paired
        if (isPaired(macId)) {
            Log.i(TAG, "Known Mac — auto-approved.")
            return true
        }

        // Unknown Mac — ask user
        var result = false
        val latch = java.util.concurrent.CountDownLatch(1)

        onPairingRequest?.invoke(macName, macId,
            {
                savePairing(macId, macName)
                result = true
                latch.countDown()
            },
            {
                result = false
                latch.countDown()
            }
        )

        // Wait up to 60s for user response
        latch.await(60, java.util.concurrent.TimeUnit.SECONDS)
        return result
    }

    // MARK: - Pairing Storage

    private fun isPaired(macId: String): Boolean {
        val paired = getPairedMacs()
        return paired.has(macId)
    }

    private fun savePairing(macId: String, macName: String) {
        val paired = getPairedMacs()
        paired.put(macId, macName)
        prefs?.edit()?.putString(PREFS_PAIRED_MACS, paired.toString())?.apply()
        Log.i(TAG, "Saved pairing with $macName ($macId)")
    }

    fun removePairing(macId: String) {
        val paired = getPairedMacs()
        paired.remove(macId)
        prefs?.edit()?.putString(PREFS_PAIRED_MACS, paired.toString())?.apply()
    }

    fun getPairedMacs(): JSONObject {
        val str = prefs?.getString(PREFS_PAIRED_MACS, "{}") ?: "{}"
        return try { JSONObject(str) } catch (e: Exception) { JSONObject() }
    }

    private fun getDeviceId(): String {
        var id = prefs?.getString("device_id", null)
        if (id == null) {
            id = java.util.UUID.randomUUID().toString()
            prefs?.edit()?.putString("device_id", id)?.apply()
        }
        return id
    }

    // MARK: - Message Dispatch

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
            "call_action" -> handleCallAction(json)
            "reply" -> handleReply(json)
            "sms_send" -> handleSMSSend(json)
            else -> Log.d(TAG, "Unknown type: ${json.optString("type")}")
        }
    }

    // MARK: - Read / Write

    private fun readPacket(input: InputStream): JSONObject? {
        val lenBuf = ByteArray(4)
        var totalRead = 0
        while (totalRead < 4) {
            val n = input.read(lenBuf, totalRead, 4 - totalRead)
            if (n < 0) return null
            totalRead += n
        }
        val length = ByteBuffer.wrap(lenBuf).int
        if (length <= 0 || length > 4_000_000) return null

        val payload = ByteArray(length)
        var read = 0
        while (read < length) {
            val n = input.read(payload, read, length - read)
            if (n < 0) return null
            read += n
        }
        return try { JSONObject(String(payload, Charsets.UTF_8)) } catch (e: Exception) { null }
    }

    private fun sendJSONDirect(payload: JSONObject) {
        val out = outputStream ?: return
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
        }
    }

    fun sendJSON(payload: JSONObject) {
        thread(name = "MacSender") { sendJSONDirect(payload) }
    }

    // MARK: - Incoming action handlers

    var onCallAction: ((String) -> Unit)? = null
    var onReply: ((String, String, String) -> Unit)? = null   // (to, message, app)
    var onSMSSend: ((String, String) -> Unit)? = null         // (to, message)

    private fun handleCallAction(json: JSONObject) {
        val action = json.optString("action")
        Log.i(TAG, "Call action from Mac: $action")
        onCallAction?.invoke(action)
    }

    private fun handleReply(json: JSONObject) {
        val to = json.optString("to")
        val message = json.optString("message")
        val app = json.optString("app")
        if (to.isNotEmpty() && message.isNotEmpty()) {
            Log.i(TAG, "Reply from Mac to $to: ${message.take(40)}")
            onReply?.invoke(to, message, app)
        }
    }

    private fun handleSMSSend(json: JSONObject) {
        val to = json.optString("to")
        val message = json.optString("message")
        if (to.isNotEmpty() && message.isNotEmpty()) {
            Log.i(TAG, "SMS from Mac to $to")
            onSMSSend?.invoke(to, message)
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
