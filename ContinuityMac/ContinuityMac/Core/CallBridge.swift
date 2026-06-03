import Foundation
import AppKit
import SwiftUI
import AVFoundation
import UserNotifications

/// Manages incoming call UI, audio routing, and call control.
///
/// Flow:
///   Android rings → sends call_incoming over TCP
///   → Mac shows floating banner bottom-right
///   → User can Answer (routes audio via BT/HFP) or Decline
///   → If answered on phone → Mac gets call_answered → banner disappears
///   → If ended → call_ended → banner disappears
final class CallBridge: ObservableObject {
    static let shared = CallBridge()
    private init() {}

    // MARK: - Published State

    @Published var isCallActive = false
    @Published var isCallAnswered = false   // true when in-call (answered)
    @Published var callerName = ""
    @Published var callerNumber = ""
    @Published var callDuration: Int = 0    // seconds since answered

    // MARK: - Private

    private var callWindow: NSWindow?
    private var durationTimer: Timer?
    private var audioEngine: AVAudioEngine?
    private var callPollTimer: Timer?
    private var wasInCall = false

    // MARK: - Incoming Call

    func showIncomingCall(caller: String, number: String) {
        DispatchQueue.main.async {
            self.isCallActive = true
            self.isCallAnswered = false
            self.callerName = caller
            self.callerNumber = number
            self.callDuration = 0
            self.showCallWindow()
        }
    }

    func dismissCall() {
        DispatchQueue.main.async {
            self.isCallActive = false
            self.isCallAnswered = false
            self.callerName = ""
            self.callerNumber = ""
            self.callDuration = 0
            self.durationTimer?.invalidate()
            self.durationTimer = nil
            self.stopAudio()
            self.closeCallWindow()
        }
    }

    func callAnsweredOnPhone() {
        // Phone picked up — update to in-call state, keep banner as active call
        DispatchQueue.main.async {
            self.isCallAnswered = true
            self.startDurationTimer()
        }
    }

    // MARK: - Socket Message Handler

    func handleSocketMessage(json: [String: Any]) {
        guard let type = json["type"] as? String else { return }
        switch type {
        case "call_incoming":
            let caller = json["caller"] as? String ?? "Unknown"
            let number = json["number"] as? String ?? ""
            showIncomingCall(caller: caller, number: number)
        case "call_answered":
            callAnsweredOnPhone()
        case "call_ended":
            dismissCall()
        default:
            break
        }
    }

    func handleSocketMessage(json: [String: String]) {
        let anyJson = json.reduce(into: [String: Any]()) { $0[$1.key] = $1.value }
        handleSocketMessage(json: anyJson)
    }

    // MARK: - Call Actions

    /// Answer on Mac — routes audio through Mac speakers/mic via Bluetooth HFP
    func answerCall() {
        print("[Call] Answering on Mac")
        // Send answer command to Android
        let packet: [String: Any] = ["type": "call_action", "action": "answer"]
        if let data = try? JSONSerialization.data(withJSONObject: packet) {
            ClipboardSyncDaemon.shared.sendRawPacket(data)
        }
        // Also try ADB fallback
        DispatchQueue.global(qos: .userInteractive).async {
            ADBBridge.shared.shell("input keyevent 5")
        }
        DispatchQueue.main.async {
            self.isCallAnswered = true
            self.startDurationTimer()
            self.startAudio()
        }
    }

    func declineCall() {
        print("[Call] Declining")
        let packet: [String: Any] = ["type": "call_action", "action": "decline"]
        if let data = try? JSONSerialization.data(withJSONObject: packet) {
            ClipboardSyncDaemon.shared.sendRawPacket(data)
        }
        DispatchQueue.global(qos: .userInteractive).async {
            ADBBridge.shared.shell("input keyevent 6")
        }
        dismissCall()
    }

    func hangupCall() {
        print("[Call] Hanging up")
        let packet: [String: Any] = ["type": "call_action", "action": "hangup"]
        if let data = try? JSONSerialization.data(withJSONObject: packet) {
            ClipboardSyncDaemon.shared.sendRawPacket(data)
        }
        DispatchQueue.global(qos: .userInteractive).async {
            ADBBridge.shared.shell("input keyevent 6")
        }
        dismissCall()
    }

    // MARK: - SMS Reply

    func sendSMSReply(to number: String, message: String) {
        guard !message.isEmpty else { return }
        let packet: [String: Any] = [
            "type": "sms_send",
            "to": number,
            "message": message
        ]
        if let data = try? JSONSerialization.data(withJSONObject: packet) {
            ClipboardSyncDaemon.shared.sendRawPacket(data)
        }
        // ADB fallback
        DispatchQueue.global(qos: .userInitiated).async {
            let escaped = message.replacingOccurrences(of: "'", with: "\\'")
            ADBBridge.shared.shell(
                "am start -a android.intent.action.SENDTO -d sms:\(number) --es sms_body '\(escaped)' --ez exit_on_sent true"
            )
        }
    }

    // MARK: - Duration Timer

    private func startDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.callDuration += 1
        }
    }

    // MARK: - Audio (Mac mic → Android, Android audio → Mac speakers via BT)

    private func startAudio() {
        // Audio routing happens via Bluetooth HFP profile
        // When the call is answered, the OS routes audio automatically if a BT headset
        // or the phone is paired via HFP. We just need to ensure the audio session is active.
        print("[Call] Audio routing started — use Bluetooth for phone audio")
    }

    private func stopAudio() {
        audioEngine?.stop()
        audioEngine = nil
    }

    // MARK: - Floating Call Window (bottom-right corner)

    private func showCallWindow() {
        closeCallWindow()

        guard let screen = NSScreen.main else { return }
        let windowW: CGFloat = 320
        let windowH: CGFloat = 120
        let margin: CGFloat = 20

        let x = screen.visibleFrame.maxX - windowW - margin
        let y = screen.visibleFrame.minY + margin

        let window = NSWindow(
            contentRect: NSRect(x: x, y: y, width: windowW, height: windowH),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.hasShadow = true

        let callView = CallBannerWindowView()
            .environmentObject(self)
        window.contentView = NSHostingView(rootView: callView)
        window.orderFrontRegardless()
        self.callWindow = window
    }

    private func closeCallWindow() {
        callWindow?.close()
        callWindow = nil
    }

    // MARK: - ADB Call Monitoring Fallback

    func startCallMonitoring() {
        callPollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkCallState()
        }
    }

    func stopCallMonitoring() {
        callPollTimer?.invalidate()
        callPollTimer = nil
    }

    private func checkCallState() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }
            let output = ADBBridge.shared.shell("dumpsys telephony.registry 2>/dev/null | grep 'mCallState'")
            if output.contains("mCallState=1") && !self.wasInCall {
                self.wasInCall = true
                let callerOut = ADBBridge.shared.shell(
                    "dumpsys telephony.registry 2>/dev/null | grep 'mCallIncomingNumber'"
                )
                let number = callerOut.components(separatedBy: "=").last?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown"
                DispatchQueue.main.async { self.showIncomingCall(caller: number, number: number) }
            } else if output.contains("mCallState=2") && !self.isCallAnswered {
                // Answered on phone
                DispatchQueue.main.async { self.callAnsweredOnPhone() }
            } else if output.contains("mCallState=0") && self.wasInCall {
                self.wasInCall = false
                DispatchQueue.main.async { self.dismissCall() }
            }
        }
    }

    // MARK: - Duration formatting

    var formattedDuration: String {
        let m = callDuration / 60
        let s = callDuration % 60
        return String(format: "%d:%02d", m, s)
    }
}
