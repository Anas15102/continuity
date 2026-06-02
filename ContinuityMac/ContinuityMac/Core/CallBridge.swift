import Foundation
import AppKit
import UserNotifications

/// Handles incoming call alerts from the Android device.
/// Shows a native macOS alert with Answer / Decline buttons.
/// Also supports sending SMS replies without picking up.
final class CallBridge: ObservableObject {
    static let shared = CallBridge()
    private init() {}

    // MARK: - Published State

    @Published var isCallActive = false
    @Published var callerName = ""
    @Published var callerNumber = ""

    // MARK: - Incoming Call

    func showIncomingCall(caller: String, number: String) {
        DispatchQueue.main.async {
            self.isCallActive = true
            self.callerName = caller
            self.callerNumber = number
        }

        // Show macOS alert panel
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "📞 Incoming Call"
            alert.informativeText = "\(caller)\n\(number)"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Answer")
            alert.addButton(withTitle: "Decline")
            alert.addButton(withTitle: "Reply with SMS")

            NSApp.activate(ignoringOtherApps: true)
            let response = alert.runModal()

            switch response {
            case .alertFirstButtonReturn:
                self.answerCall()
            case .alertSecondButtonReturn:
                self.declineCall()
            case .alertThirdButtonReturn:
                self.showSMSReply(to: number)
            default:
                break
            }
        }
    }

    func dismissCall() {
        DispatchQueue.main.async {
            self.isCallActive = false
            self.callerName = ""
            self.callerNumber = ""
        }
    }

    /// Handle messages routed from ClipboardSyncDaemon socket
    func handleSocketMessage(json: [String: String]) {
        switch json["type"] {
        case "call_incoming":
            if let caller = json["caller"], let number = json["number"] {
                showIncomingCall(caller: caller, number: number)
            }
        case "call_ended":
            dismissCall()
        default:
            break
        }
    }

    // MARK: - Call Actions

    /// Answer the call via ADB key event (KEYCODE_CALL = 5)
    func answerCall() {
        DispatchQueue.global(qos: .userInteractive).async {
            ADBBridge.shared.shell("input keyevent 5")
        }
        dismissCall()
    }

    /// Decline the call via ADB key event (KEYCODE_ENDCALL = 6)
    func declineCall() {
        DispatchQueue.global(qos: .userInteractive).async {
            ADBBridge.shared.shell("input keyevent 6")
        }
        dismissCall()
    }

    // MARK: - SMS Reply

    func showSMSReply(to number: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Reply to \(number)"
            alert.alertStyle = .informational

            let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
            input.placeholderString = "Type your message..."
            alert.accessoryView = input
            alert.addButton(withTitle: "Send")
            alert.addButton(withTitle: "Cancel")

            if alert.runModal() == .alertFirstButtonReturn {
                let message = input.stringValue
                if !message.isEmpty {
                    self.sendSMS(to: number, message: message)
                }
            }
        }
    }

    /// Sends an SMS via ADB intent
    func sendSMS(to number: String, message: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let escaped = message.replacingOccurrences(of: "'", with: "\\'")
            // Open SMS app with pre-filled message
            ADBBridge.shared.shell(
                "am start -a android.intent.action.SENDTO -d sms:\(number) --es sms_body '\(escaped)' --ez exit_on_sent true"
            )
            // Simulate send button tap after a short delay
            Thread.sleep(forTimeInterval: 1.0)
            ADBBridge.shared.shell("input keyevent 66") // ENTER
        }
    }

    // MARK: - ADB Call Monitoring
    // Polls call state via ADB when companion APK is not installed

    private var callPollTimer: Timer?
    private var wasInCall = false

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
            // mCallState=1 = ringing, mCallState=2 = offhook, mCallState=0 = idle
            if output.contains("mCallState=1") && !self.wasInCall {
                self.wasInCall = true
                // Get caller info
                let callerOutput = ADBBridge.shared.shell(
                    "dumpsys telephony.registry 2>/dev/null | grep 'mCallIncomingNumber'"
                )
                let number = callerOutput
                    .components(separatedBy: "=").last?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown"
                DispatchQueue.main.async {
                    self.showIncomingCall(caller: number, number: number)
                }
            } else if output.contains("mCallState=0") && self.wasInCall {
                self.wasInCall = false
                self.dismissCall()
            }
        }
    }
}
