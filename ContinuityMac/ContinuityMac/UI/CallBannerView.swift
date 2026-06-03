import SwiftUI

/// Floating bottom-right call banner window content.
/// Shows when a call comes in and stays during active call.
struct CallBannerWindowView: View {
    @EnvironmentObject var callBridge: CallBridge
    @State private var showSMSReply = false
    @State private var smsText = ""

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.25), radius: 16, y: 4)

            if callBridge.isCallAnswered {
                activeCallView
            } else {
                incomingCallView
            }
        }
        .frame(width: 320, height: showSMSReply ? 160 : 110)
        .animation(.spring(response: 0.3), value: showSMSReply)
        .animation(.spring(response: 0.3), value: callBridge.isCallAnswered)
    }

    // MARK: - Incoming Call

    private var incomingCallView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Pulsing green ring
                ZStack {
                    Circle()
                        .stroke(Color.green.opacity(0.3), lineWidth: 8)
                        .frame(width: 44, height: 44)
                    Circle()
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: "phone.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.green)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Incoming Call")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(callBridge.callerName.isEmpty ? callBridge.callerNumber : callBridge.callerName)
                        .font(.system(size: 14, weight: .bold))
                        .lineLimit(1)
                    if !callBridge.callerName.isEmpty && !callBridge.callerNumber.isEmpty {
                        Text(callBridge.callerNumber)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                VStack(spacing: 6) {
                    // Decline
                    Button(action: { callBridge.declineCall() }) {
                        Image(systemName: "phone.down.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(.red))
                    }
                    .buttonStyle(.plain)
                    .help("Decline")

                    // Answer
                    Button(action: { callBridge.answerCall() }) {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(.green))
                    }
                    .buttonStyle(.plain)
                    .help("Answer")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // SMS Reply row
            if showSMSReply {
                Divider().opacity(0.3)
                HStack(spacing: 8) {
                    TextField("Reply with SMS...", text: $smsText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                    Button("Send") {
                        callBridge.sendSMSReply(to: callBridge.callerNumber, message: smsText)
                        smsText = ""
                        showSMSReply = false
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(smsText.isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            // SMS reply toggle
            Button(showSMSReply ? "Cancel" : "Reply with SMS") {
                withAnimation { showSMSReply.toggle() }
            }
            .font(.system(size: 10))
            .foregroundStyle(Color.accentColor)
            .buttonStyle(.plain)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Active Call (answered)

    private var activeCallView: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "waveform")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.green)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(callBridge.callerName.isEmpty ? callBridge.callerNumber : callBridge.callerName)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Circle().fill(.green).frame(width: 6, height: 6)
                    Text(callBridge.formattedDuration)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Hangup
            Button(action: { callBridge.hangupCall() }) {
                Image(systemName: "phone.down.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(.red))
            }
            .buttonStyle(.plain)
            .help("Hang Up")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

/// Legacy in-popover banner (kept for reference, actual banner is the window above)
struct CallBannerView: View {
    @EnvironmentObject var callBridge: CallBridge

    var body: some View {
        EmptyView() // Actual UI is the floating window
    }
}
