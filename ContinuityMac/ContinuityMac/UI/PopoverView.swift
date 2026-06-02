import SwiftUI

struct PopoverView: View {
    @EnvironmentObject var mirroring: MirroringSessionManager
    @EnvironmentObject var crossControl: PeripheralRoutingEngine
    @EnvironmentObject var clipboard: ClipboardSyncDaemon
    @EnvironmentObject var fileTransfer: FileTransferEngine
    @EnvironmentObject var hotspot: HotspotController
    @EnvironmentObject var discovery: DeviceDiscovery
    @EnvironmentObject var wifi: WifiConnectionManager
    @EnvironmentObject var notifBridge: NotificationBridge
    @EnvironmentObject var callBridge: CallBridge

    @State private var showNotifications = false

    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                headerSection
                Divider().opacity(0.3)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        featureToggles
                        Divider().opacity(0.3).padding(.horizontal, 16)
                        ShareHubView().environmentObject(fileTransfer)
                    }
                }

                Divider().opacity(0.3)
                footerSection
            }
            .padding(.vertical, 8)
        }
        .frame(width: 320, height: 520)
        .sheet(isPresented: $showNotifications) {
            NotificationsView()
                .environmentObject(notifBridge)
                .environmentObject(callBridge)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "iphone")
                .font(.system(size: 26, weight: .light))

            VStack(alignment: .leading, spacing: 2) {
                Text(discovery.connectedDeviceName ?? "No Device")
                    .font(.system(size: 14, weight: .semibold))
                HStack(spacing: 4) {
                    Circle()
                        .fill(discovery.isConnected ? Color.green : Color.secondary)
                        .frame(width: 6, height: 6)
                    Text(discovery.isConnected
                         ? (wifi.isWifiConnected ? "Wi-Fi" : "USB")
                         : "Searching...")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Notification badge
            Button {
                showNotifications = true
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell")
                        .font(.system(size: 16))
                    if !notifBridge.recentNotifications.isEmpty {
                        Circle()
                            .fill(.red)
                            .frame(width: 8, height: 8)
                            .offset(x: 4, y: -4)
                    }
                }
            }
            .buttonStyle(.plain)

            if discovery.isConnected {
                BatteryView(level: discovery.batteryLevel)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Feature Toggles

    private var featureToggles: some View {
        VStack(spacing: 4) {
            // Wi-Fi toggle — enable wireless ADB
            FeatureRow(
                icon: wifi.isWifiConnected ? "wifi" : "cable.connector",
                title: wifi.isWifiConnected ? "Wireless Mode" : "Enable Wi-Fi Mode",
                subtitle: wifi.statusMessage,
                isActive: wifi.isWifiConnected,
                action: {
                    if wifi.isWifiConnected {
                        wifi.disconnect()
                    } else {
                        wifi.enableWifiMode { success in
                            print("[WiFi] Setup: \(success)")
                        }
                    }
                }
            )

            FeatureRow(
                icon: "rectangle.on.rectangle",
                title: "Screen Mirror",
                subtitle: mirroring.isMirrorActive ? "Active — tap to stop" : "Tap to start",
                isActive: mirroring.isMirrorActive,
                action: {
                    if mirroring.isMirrorActive {
                        mirroring.terminateMirroringSession()
                    } else {
                        mirroring.establishMirroringSession(mode: .mirror)
                    }
                }
            )

            FeatureRow(
                icon: crossControl.permissionDenied ? "lock.shield" : "cursorarrow.rays",
                title: "Cross Control",
                subtitle: crossControl.permissionDenied
                    ? "Grant Accessibility permission"
                    : crossControl.isCursorRoutingActive
                        ? "Move mouse to right edge"
                        : "Share mouse & keyboard",
                isActive: crossControl.isCursorRoutingActive,
                action: {
                    if crossControl.isCursorRoutingActive {
                        crossControl.releaseControl()
                    } else {
                        crossControl.initializeCursorTracker()
                    }
                }
            )

            FeatureRow(
                icon: "doc.on.clipboard",
                title: "Clipboard Sync",
                subtitle: clipboard.isRunning
                    ? (clipboard.lastSyncedText.isEmpty ? "Listening..." : "Last: \(clipboard.lastSyncedText.prefix(20))...")
                    : "Tap to enable",
                isActive: clipboard.isRunning,
                action: {
                    if clipboard.isRunning { clipboard.stop() } else { clipboard.start() }
                }
            )

            FeatureRow(
                icon: "personalhotspot",
                title: "Smart Hotspot",
                subtitle: hotspot.isActive ? "Hotspot On" : "Enable phone hotspot",
                isActive: hotspot.isActive,
                action: { hotspot.toggle() }
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            Button(action: { NSApp.terminate(nil) }) {
                HStack(spacing: 4) {
                    Image(systemName: "power")
                        .font(.system(size: 11, weight: .medium))
                    Text("Quit")
                        .font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.red.opacity(0.12))
                .foregroundStyle(Color.red)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Continuity")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Reusable Components (kept here to avoid duplicate)

struct FeatureRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isActive ? Color.accentColor : Color.secondary.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(isActive ? .white : .primary)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Circle()
                    .fill(isActive ? Color.green : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
        }
        .buttonStyle(.plain)
    }
}

struct BatteryView: View {
    let level: Int
    private var color: Color {
        level > 50 ? .green : level > 20 ? .yellow : .red
    }
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: batteryIcon)
                .foregroundStyle(color)
            Text("\(level)%")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
    private var batteryIcon: String {
        switch level {
        case 76...100: return "battery.100"
        case 51...75:  return "battery.75"
        case 26...50:  return "battery.50"
        case 11...25:  return "battery.25"
        default:       return "battery.0"
        }
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blendingMode
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blendingMode
    }
}
