import SwiftUI

/// Floating call banner that appears at the top of the screen
/// when an incoming call is detected on the phone.
struct CallBannerView: View {
    @EnvironmentObject var callBridge: CallBridge
    @State private var isVisible = false

    var body: some View {
        Group {
            if callBridge.isCallActive {
                VStack {
                    callBanner
                        .transition(.move(edge: .top).combined(with: .opacity))
                    Spacer()
                }
                .animation(.spring(response: 0.4), value: callBridge.isCallActive)
            }
        }
    }

    private var callBanner: some View {
        HStack(spacing: 14) {
            // Pulsing phone icon
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.2))
                    .frame(width: 44, height: 44)
                Image(systemName: "phone.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.green)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Incoming Call")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(callBridge.callerName.isEmpty ? callBridge.callerNumber : callBridge.callerName)
                    .font(.system(size: 14, weight: .semibold))
                if !callBridge.callerName.isEmpty {
                    Text(callBridge.callerNumber)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Decline
            Button {
                callBridge.declineCall()
            } label: {
                Image(systemName: "phone.down.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(.red))
            }
            .buttonStyle(.plain)

            // Answer
            Button {
                callBridge.answerCall()
            } label: {
                Image(systemName: "phone.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(.green))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}
