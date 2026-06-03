import SwiftUI
import CoreImage.CIFilterBuiltins

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
    @EnvironmentObject var pairing: PairingManager

    @State private var showNotifications = false

    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Always show header
                headerSection
                Divider().opacity(0.3)

                if clipboard.isSocketConnected {
                    // CONNECTED — show full feature UI
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 0) {
                            featureToggles
                            Divider().opacity(0.3).padding(.horizontal, 16)
                            ShareHubView().environmentObject(fileTransfer)
                        }
                    }
                } else {
                    // NOT CONNECTED — show pairing / device list
                    notConnectedView
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
        .sheet(isPresented: $pairing.showPairingSheet) {
            PairingView().environmentObject(pairing)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 12) {
            // Phone icon with connection indicator
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "iphone")
                    .font(.system(size: 26, weight: .light))
                Circle()
                    .fill(clipboard.isSocketConnected ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 9, height: 9)
                    .offset(x: 2, y: 2)
            }

            VStack(alignment: .leading, spacing: 2) {
                if clipboard.isSocketConnected {
                    Text(clipboard.connectedDeviceName.isEmpty
                         ? (discovery.connectedDeviceName ?? "Android Device")
                         : clipboard.connectedDeviceName)
                        .font(.system(size: 14, weight: .semibold))
                    HStack(spacing: 4) {
                        Circle().fill(Color.green).frame(width: 6, height: 6)
                        Text("Connected · \(discovery.deviceIP ?? "")")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("No Device Connected")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(pairing.pairedDevices.isEmpty ? "Tap + to pair your phone" : "Tap to connect")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Notifications bell (only when connected)
            if clipboard.isSocketConnected {
                Button { showNotifications = true } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "bell").font(.system(size: 16))
                        if !notifBridge.recentNotifications.isEmpty {
                            Circle().fill(.red).frame(width: 8, height: 8).offset(x: 4, y: -4)
                        }
                    }
                }
                .buttonStyle(.plain)

                if discovery.batteryLevel > 0 {
                    BatteryView(level: discovery.batteryLevel)
                }
            }

            // Pair new device button — always visible
            Button {
                pairing.showPairingSheet = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .help("Pair new device")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Not Connected View

    private var notConnectedView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {

                if pairing.pairedDevices.isEmpty {
                    // No devices ever paired — show big QR prompt
                    firstTimePairView
                } else {
                    // Has saved devices — show them with connect buttons
                    savedDevicesView
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
    }

    private var firstTimePairView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "iphone.and.arrow.forward")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text("Connect your Android phone")
                    .font(.system(size: 15, weight: .semibold))
                Text("Pair once — auto-connect every time")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            // Show Mac's QR code for phone to scan
            MacQRCodeView()

            VStack(spacing: 4) {
                Text("Open Continuity on your phone")
                    .font(.system(size: 12, weight: .medium))
                Text("and scan this QR code to pair")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            // Manual IP fallback
            Button("Enter IP manually instead") {
                pairing.showPairingSheet = true
            }
            .font(.system(size: 11))
            .foregroundStyle(Color.accentColor)
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var savedDevicesView: some View {
        VStack(spacing: 12) {
            // Saved devices
            VStack(spacing: 2) {
                HStack {
                    Text("Saved Devices")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                ForEach(pairing.pairedDevices) { device in
                    SavedDeviceRow(device: device)
                        .environmentObject(pairing)
                }
            }

            Divider().opacity(0.3)

            // Show QR for new device
            VStack(spacing: 8) {
                Text("Pair another device")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                MacQRCodeView()

                Text("Scan with the Continuity Android app")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Feature Toggles (only shown when connected)

    private var featureToggles: some View {
        VStack(spacing: 4) {
            FeatureRow(
                icon: wifi.isWifiConnected ? "wifi" : "cable.connector",
                title: wifi.isWifiConnected ? "Wireless Mode" : "Enable Wi-Fi Mode",
                subtitle: wifi.statusMessage,
                isActive: wifi.isWifiConnected,
                action: {
                    if wifi.isWifiConnected { wifi.disconnect() }
                    else { wifi.enableWifiMode { _ in } }
                }
            )
            FeatureRow(
                icon: "rectangle.on.rectangle",
                title: "Screen Mirror",
                subtitle: mirroring.isMirrorActive ? "Active — tap to stop" : "Tap to start",
                isActive: mirroring.isMirrorActive,
                action: {
                    if mirroring.isMirrorActive { mirroring.terminateMirroringSession() }
                    else { mirroring.establishMirroringSession(mode: .mirror) }
                }
            )
            FeatureRow(
                icon: crossControl.permissionDenied ? "lock.shield" : "cursorarrow.rays",
                title: "Cross Control",
                subtitle: crossControl.permissionDenied
                    ? "Grant Accessibility permission"
                    : crossControl.isCursorRoutingActive ? "Move mouse to right edge" : "Share mouse & keyboard",
                isActive: crossControl.isCursorRoutingActive,
                action: {
                    if crossControl.isCursorRoutingActive { crossControl.releaseControl() }
                    else { crossControl.initializeCursorTracker() }
                }
            )
            FeatureRow(
                icon: "doc.on.clipboard",
                title: "Clipboard Sync",
                subtitle: clipboard.isRunning
                    ? (clipboard.lastSyncedText.isEmpty ? "Syncing..." : "Last: \(clipboard.lastSyncedText.prefix(20))...")
                    : "Tap to enable",
                isActive: clipboard.isRunning,
                action: { if clipboard.isRunning { clipboard.stop() } else { clipboard.start() } }
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
                    Image(systemName: "power").font(.system(size: 11, weight: .medium))
                    Text("Quit").font(.system(size: 12, weight: .medium))
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

// MARK: - Mac QR Code View
// Shows a QR code that the PHONE scans to initiate pairing.
// The QR contains the Mac's identity so Android knows who is connecting.

struct MacQRCodeView: View {
    private var qrContent: String {
        // continuity://mac-pair?id=UUID&name=MacName
        let id = ClipboardSyncDaemon.macDeviceId
        let name = ClipboardSyncDaemon.macDeviceName
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Mac"
        return "continuity://mac-pair?id=\(id)&name=\(name)"
    }

    var body: some View {
        if let image = generateQR(from: qrContent) {
            Image(nsImage: image)
                .interpolation(.none)
                .resizable()
                .frame(width: 160, height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
        }
    }

    private func generateQR(from string: String) -> NSImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: 160, height: 160))
    }
}

// MARK: - Saved Device Row

struct SavedDeviceRow: View {
    @EnvironmentObject var pairing: PairingManager
    let device: PairedDevice

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 34, height: 34)
                Image(systemName: "iphone")
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(device.name)
                    .font(.system(size: 13, weight: .medium))
                Text(device.ip)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Connect") {
                pairing.switchTo(device)
            }
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.accentColor.opacity(0.15))
            .foregroundStyle(Color.accentColor)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
        .contextMenu {
            Button("Remove", role: .destructive) {
                pairing.removeDevice(device)
            }
        }
    }
}

// MARK: - Reusable Components

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
                    Text(title).font(.system(size: 13, weight: .medium))
                    Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
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
    private var color: Color { level > 50 ? .green : level > 20 ? .yellow : .red }
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: batteryIcon).foregroundStyle(color)
            Text("\(level)%").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
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
        v.material = material; v.blendingMode = blendingMode; v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material; v.blendingMode = blendingMode
    }
}
