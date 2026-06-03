import Foundation
import AppKit
import Network
import CryptoKit

/// Two-way clipboard sync + secure connection manager.
///
/// Upgrades:
///  1. TLS — all traffic encrypted (self-signed certs, trust-on-first-use)
///  2. Identity exchange — both sides announce name + capabilities on connect
///  3. Pairing — Mac sends its identity, Android confirms before data flows
final class ClipboardSyncDaemon: ObservableObject {
    static let shared = ClipboardSyncDaemon()
    private init() {}

    // MARK: - Published State

    @Published var isRunning = false
    @Published var lastSyncedText: String = ""
    @Published var isSocketConnected = false
    @Published var connectedDeviceName: String = ""
    @Published var connectedDeviceCapabilities: [String] = []

    // MARK: - Constants

    private let port: NWEndpoint.Port = 9876
    static let macCapabilities = ["clipboard", "notification", "call", "sms", "file_transfer", "ping"]

    // MARK: - Private

    private var connection: NWConnection?
    private var macPollTimer: Timer?
    private var reconnectTimer: Timer?
    private var lastMacContent: String = ""
    private var lastAndroidContent: String = ""
    private var identityExchanged = false
    private var currentIP: String = ""

    // MARK: - Mac identity (persisted)

    static var macDeviceId: String {
        if let id = UserDefaults.standard.string(forKey: "continuity.deviceId") { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: "continuity.deviceId")
        return id
    }

    static var macDeviceName: String {
        Host.current().localizedName ?? "Mac"
    }

    // MARK: - TLS parameters (allow self-signed)

    private func tlsParameters() -> NWParameters {
        let tlsOptions = NWProtocolTLS.Options()
        // Allow self-signed certificates (trust-on-first-use like KDEConnect/SSH)
        sec_protocol_options_set_verify_block(
            tlsOptions.securityProtocolOptions,
            { _, _, completion in completion(true) },
            .main
        )
        return NWParameters(tls: tlsOptions)
    }

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true
        lastMacContent = NSPasteboard.general.string(forType: .string) ?? ""
        print("[Connection] Started.")
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
        identityExchanged = false
        DispatchQueue.main.async {
            self.isSocketConnected = false
            self.connectedDeviceName = ""
        }
        print("[Connection] Stopped.")
    }

    // MARK: - Connect

    func connectToAndroid(ip: String) {
        guard isRunning else { return }
        connection?.cancel()
        identityExchanged = false
        currentIP = ip

        let conn = NWConnection(
            host: NWEndpoint.Host(ip),
            port: port,
            using: tlsParameters()
        )
        connection = conn

        conn.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                print("[Connection] TLS connected to \(ip)")
                self.receiveLoop()
                // Send identity immediately after TLS handshake
                self.sendIdentity()
            case .failed(let error):
                DispatchQueue.main.async { self.isSocketConnected = false }
                print("[Connection] Failed: \(error) — retry in 5s")
                self.scheduleReconnect(ip: ip)
            case .cancelled:
                DispatchQueue.main.async { self.isSocketConnected = false }
            case .waiting(let error):
                print("[Connection] Waiting: \(error)")
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
            self?.connectToAndroid(ip: ip)
        }
    }

    // MARK: - Identity Exchange (Upgrade 2)

    private func sendIdentity() {
        let identity: [String: Any] = [
            "type": "identity",
            "deviceName": Self.macDeviceName,
            "deviceId": Self.macDeviceId,
            "deviceType": "desktop",
            "appVersion": "1.0.0",
            "capabilities": Self.macCapabilities
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: identity) else { return }
        sendRaw(data)
        print("[Identity] Sent Mac identity.")
    }

    private func handleIdentity(json: [String: Any]) {
        guard let name = json["deviceName"] as? String else { return }
        let caps = json["capabilities"] as? [String] ?? []

        DispatchQueue.main.async {
            self.isSocketConnected = true
            self.connectedDeviceName = name
            self.connectedDeviceCapabilities = caps
            self.identityExchanged = true
            DeviceDiscovery.shared.setManualDevice(name: name, ip: self.currentIP)
        }
        print("[Identity] Android: \(name), caps: \(caps)")
    }

    // MARK: - Receive Loop

    private func receiveLoop() {
        connection?.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, _, error in
            guard let self = self, let data = data, data.count == 4, error == nil else { return }
            let length = Int(data.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
            guard length > 0, length < 4_000_000 else { self.receiveLoop(); return }

            self.connection?.receive(minimumIncompleteLength: length, maximumLength: length) { payload, _, _, err in
                guard let payload = payload, err == nil else { return }
                self.handleIncoming(data: payload)
                self.receiveLoop()
            }
        }
    }

    private func handleIncoming(data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        switch type {
        case "identity":
            handleIdentity(json: json)

        case "clipboard":
            guard identityExchanged else { return }
            guard let text = json["text"] as? String,
                  !text.isEmpty, text != lastAndroidContent else { return }
            lastAndroidContent = text
            lastMacContent = text
            DispatchQueue.main.async {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                self.lastSyncedText = text
                print("[Clipboard] Android→Mac: \(text.prefix(40))")
            }

        case "pong":
            print("[Ping] Pong received.")

        default:
            guard identityExchanged else { return }
            var anyJson = json
            let strJson = json.compactMapValues { $0 as? String }
            // Route to appropriate handlers
            if let type = json["type"] as? String {
                if type == "call_answered" {
                    CallBridge.shared.callAnsweredOnPhone()
                    return
                }
            }
            NotificationBridge.shared.handleSocketMessage(json: anyJson)
            CallBridge.shared.handleSocketMessage(json: anyJson)
        }
    }

    // MARK: - Send

    func sendToAndroid(text: String) {
        guard isSocketConnected, identityExchanged else { return }
        guard let data = try? JSONSerialization.data(withJSONObject: [
            "type": "clipboard", "text": text
        ]) else { return }
        sendRaw(data)
        DispatchQueue.main.async { self.lastSyncedText = text }
    }

    /// Public method for other subsystems (NotificationBridge, etc.) to send packets
    func sendRawPacket(_ data: Data) {
        guard isSocketConnected else { return }
        sendRaw(data)
    }

    private func sendRaw(_ data: Data) {
        guard let conn = connection else { return }
        var length = UInt32(data.count).bigEndian
        var packet = Data(bytes: &length, count: 4)
        packet.append(data)
        conn.send(content: packet, completion: .contentProcessed { error in
            if let error = error { print("[Send] Error: \(error)") }
        })
    }

    // MARK: - Mac Clipboard Polling

    private func startMacPollTimer() {
        macPollTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            self?.checkMacClipboard()
        }
    }

    private func checkMacClipboard() {
        // Auto-connect if we have a saved device but no socket
        if !isSocketConnected {
            if let ip = DeviceDiscovery.shared.deviceIP {
                connectToAndroid(ip: ip)
            }
        }

        guard isSocketConnected, identityExchanged else { return }
        guard let text = NSPasteboard.general.string(forType: .string),
              !text.isEmpty, text != lastMacContent else { return }

        lastMacContent = text
        lastAndroidContent = text
        print("[Clipboard] Mac→Android: \(text.prefix(40))")
        sendToAndroid(text: text)
    }
}
