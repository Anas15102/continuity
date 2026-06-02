import SwiftUI

/// Dedicated window that shows mirroring controls and mode selector.
struct MirrorWindowView: View {
    @EnvironmentObject var mirroring: MirroringSessionManager
    @State private var selectedMode: MirroringMode = .mirror

    var body: some View {
        VStack(spacing: 20) {
            // Title
            HStack {
                Image(systemName: "iphone.and.arrow.forward")
                    .font(.title2)
                Text("Screen Mirror")
                    .font(.title2.bold())
                Spacer()
            }
            .padding(.horizontal)

            // Mode picker
            Picker("Mode", selection: $selectedMode) {
                Text("Mirror").tag(MirroringMode.mirror)
                Text("App Stream").tag(MirroringMode.appStream)
                Text("Desktop").tag(MirroringMode.desktop)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            // Mode description
            Text(selectedMode.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()

            // Status indicator
            if mirroring.isMirrorActive || mirroring.isAppStreamActive || mirroring.isDesktopModeActive {
                HStack {
                    Circle().fill(.green).frame(width: 8, height: 8)
                    Text("Session active — scrcpy running")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Action button
            Button(action: handleButton) {
                HStack {
                    Image(systemName: isAnyActive ? "stop.fill" : "play.fill")
                    Text(isAnyActive ? "Stop Session" : "Start \(selectedMode.label)")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(isAnyActive ? .red : .accentColor)
            .padding(.horizontal)
            .padding(.bottom)
        }
        .padding(.top)
        .frame(minWidth: 360, minHeight: 280)
    }

    private var isAnyActive: Bool {
        mirroring.isMirrorActive || mirroring.isAppStreamActive || mirroring.isDesktopModeActive
    }

    private func handleButton() {
        if isAnyActive {
            mirroring.terminateMirroringSession()
        } else {
            mirroring.establishMirroringSession(mode: selectedMode)
        }
    }
}

// MARK: - Mode descriptions

extension MirroringMode {
    var label: String {
        switch self {
        case .mirror:    return "Mirror"
        case .appStream: return "App Stream"
        case .desktop:   return "Desktop"
        }
    }

    var description: String {
        switch self {
        case .mirror:
            return "Mirror your phone screen in a window on your Mac."
        case .appStream:
            return "Stream a single Android app in its own floating window."
        case .desktop:
            return "Run Android in full desktop mode with window management."
        }
    }
}
