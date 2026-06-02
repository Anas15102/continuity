import Foundation
import AppKit
import Network

/// Two-way clipboard sync between Mac and Android.
///
/// Architecture: Android app runs a TCP server on port 9876.
/// This daemon connects TO the Android device (client role).
/// - Mac → Android: NSPasteboard poll every 0.8s → send JSON over TCP
/// - Android → Mac: receive JSON message → write to NSPasteboard
final class ClipboardSyncDaemon: ObservableObject {
    static let shared = ClipboardSyncDaemon()
    private init() {}

    // MARK: - Published State

    @Published var isRunning = false
    @Published var lastSyncedText: String = ""
    @Published var isSocketConnected = false

    // MARK: - Private

    private let port: NWEndpoint.Port = 9876
    private var connection: NWConnection?
    private var macPollTimer: Timer?
    private var reconnectTimer: Timer?
    private var lastMacContent: String = ""
    private var lastAndroidContent: String = ""

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true
        lastMacContent = NSPasteboard.general.string(forType: .string) ?? ""
        print("[Clipboard] Daemon started.")

        // Try to connect if we already have a device IP
        if let ip = DeviceDiscovery.shared.deviceIP {
            connectToAndroid(ip: ip)
        }
        // Also observe device IP changes
        startMacPollTimer()
    }

    func stop() {
        isRunning = false
        macPollTimer?.invalidate()
        macPollTimer = nil
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        connection?.cancel()
        connection = nil
        DispatchQueue.main.async { self.isSocketConnected = false }
        print("[Clipboard] Daemon stopped.")
    }

    // MARK: - Connect to Android

    func connectToAndroid(ip: String) {
        connection?.cancel()
        let host = NWEndpoint.Host(ip)
        let conn = NWConnection(host: host, port: port, using: .tcp)
        connection = conn

        conn.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                DispatchQueue.main.async { self.isSocketConnected = true }
                print("[Clipboard] Connected to Android at \(ip):\(self.port)")
                self.receiveLoop()
            case .failed(let error):
                DispatchQueue.main.async { self.isSocketConnected = false }
                print("[Clipboard] Connection failed: \(error) — retrying in 5s")
                self.scheduleReconnect(ip: ip)
            case .waiting(let error):
                print("[Clipboard] Waiting: \(error)")
            case .cancelled:
                DispatchQueue.main.async { self.isSocketConnected = false }
            default:
                break
            }
        }

        conn.start(queue: .global(qos: .background))
    }

    private func scheduleReconnect(ip: String) {
        guard isRunning else { return }
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            guard let self = self, self.isRunning else { return }
            self.connectToAndroid(ip: ip)
        }
    }

    // MARK: - Receive Loop (Android → Mac)

    private func receiveLoop() {
        // Read 4-byte length prefix first
        connection?.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, isDone, error in
            guard let self = self, let data = data, data.count == 4, error == nil else {
                if let error = error { print("[Clipboard] Receive error: \(error)") }
                return
            }
            let length = Int(data.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
            guard length > 0, length < 4_000_000 else {
                self.receiveLoop()
                return
            }
            // Read the actual payload
            self.connection?.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] payload, _, _, err in
                guard let self = self, let payload = payload, err == nil else { return }
                self.handleIncoming(data: payload)
                if !isDone { self.receiveLoop() }
            }
        }
    }

    private func handleIncoming(data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let type = json["type"] else { return }

        switch type {
        case "clipboard":
            guard let text = json["text"], !text.isEmpty, text != lastAndroidContent else { return }
            lastAndroidContent = text
            lastMacContent = text
            DispatchQueue.main.async {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                self.lastSyncedText = text
                print("[Clipboard] Android→Mac: \(text.prefix(40))")
            }
        case "pong":
            print("[Clipboard] Pong received.")
        default:
            // Route other message types to their handlers
            NotificationBridge.shared.handleSocketMessage(json: json)
            CallBridge.shared.handleSocketMessage(json: json)
        }
    }

    // MARK: - Send to Android (Mac → Android)

    private func startMacPollTimer() {
        macPollTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            self?.checkMacClipboard()
        }
    }

    private func checkMacClipboard() {
        // Try to connect if we have a device IP but no socket
        if !isSocketConnected, let ip = DeviceDiscovery.shared.deviceIP {
            connectToAndroid(ip: ip)
        }

        guard isSocketConnected else { return }
        guard let text = NSPasteboard.general.string(forType: .string),
              !text.isEmpty,
              text != lastMacContent else { return }

        lastMacContent = text
        lastAndroidContent = text
        print("[Clipboard] Mac→Android: \(text.prefix(40))")
        sendToAndroid(text: text)
    }

    func sendToAndroid(text: String) {
        guard let conn = connection, isSocketConnected else { return }
        guard let dict = try? JSONSerialization.data(withJSONObject: ["type": "clipboard", "text": text]) else { return }
        var length = UInt32(dict.count).bigEndian
        var packet = Data(bytes: &length, count: 4)
        packet.append(dict)
        conn.send(content: packet, completion: .contentProcessed { error in
            if let error = error {
                print("[Clipboard] Send error: \(error)")
            }
        })
        DispatchQueue.main.async { self.lastSyncedText = text }
    }
}
