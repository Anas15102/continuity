import SwiftUI
import AVFoundation

/// Sheet shown when user clicks "Pair New Device".
/// Shows a camera feed and scans for the QR code from the Android app.
struct PairingView: View {
    @EnvironmentObject var pairing: PairingManager
    @Environment(\.dismiss) var dismiss

    @State private var manualIP = ""
    @State private var showManual = false
    @State private var statusMessage = "Point camera at the QR code on your phone"
    @State private var paired = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Pair New Device")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding()

            Divider()

            if paired {
                // Success
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.green)
                    Text("Device Paired!")
                        .font(.title2.bold())
                    Text("Your devices are now connected.\nThey'll auto-connect every time both apps are running.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .font(.callout)
                    Button("Done") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            } else if showManual {
                // Manual IP entry
                VStack(spacing: 16) {
                    Image(systemName: "network")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)

                    Text("Enter IP Address")
                        .font(.headline)

                    Text("Find the IP address shown in the Continuity app on your phone")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    TextField("192.168.1.xxx", text: $manualIP)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 16, design: .monospaced))
                        .frame(width: 200)

                    HStack(spacing: 12) {
                        Button("Back") { showManual = false }
                            .buttonStyle(.bordered)
                        Button("Connect") {
                            guard !manualIP.isEmpty else { return }
                            pairing.pairFromIP(manualIP)
                            paired = true
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(manualIP.isEmpty)
                    }
                }
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            } else {
                // QR Scanner
                VStack(spacing: 12) {
                    QRScannerView { scanned in
                        if pairing.pairFromURL(scanned) {
                            paired = true
                        }
                    }
                    .frame(width: 320, height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.accentColor, lineWidth: 2)
                    )

                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button("Enter IP manually instead") {
                        showManual = true
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.accentColor)
                }
                .padding()
            }
        }
        .frame(width: 380, height: 420)
    }
}

// MARK: - QR Scanner (AVFoundation)

struct QRScannerView: NSViewRepresentable {
    var onScanned: (String) -> Void

    func makeNSView(context: Context) -> QRCaptureView {
        let view = QRCaptureView()
        view.onScanned = onScanned
        view.startScanning()
        return view
    }

    func updateNSView(_ nsView: QRCaptureView, context: Context) {}
}

class QRCaptureView: NSView, AVCaptureMetadataOutputObjectsDelegate {
    var onScanned: ((String) -> Void)?
    private var session: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?

    func startScanning() {
        let session = AVCaptureSession()
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            return
        }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = bounds
        layer = preview
        wantsLayer = true

        self.previewLayer = preview
        self.session = session

        DispatchQueue.global(qos: .background).async {
            session.startRunning()
        }
    }

    override func layout() {
        super.layout()
        previewLayer?.frame = bounds
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput objects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard let obj = objects.first as? AVMetadataMachineReadableCodeObject,
              let str = obj.stringValue else { return }
        session?.stopRunning()
        onScanned?(str)
    }
}

// MARK: - Devices List (shown in popover)

struct PairedDevicesView: View {
    @EnvironmentObject var pairing: PairingManager
    @State private var showPairingSheet = false

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Devices")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: { showPairingSheet = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.accentColor)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)

            if pairing.pairedDevices.isEmpty {
                Button(action: { showPairingSheet = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.system(size: 14))
                        Text("Pair your Android phone")
                            .font(.system(size: 12))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.accentColor.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
            } else {
                ForEach(pairing.pairedDevices) { device in
                    DeviceRow(device: device)
                }
            }
        }
        .sheet(isPresented: $showPairingSheet) {
            PairingView().environmentObject(pairing)
        }
    }
}

struct DeviceRow: View {
    @EnvironmentObject var pairing: PairingManager
    let device: PairedDevice

    var isActive: Bool { pairing.activeDeviceID == device.id }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "iphone")
                .font(.system(size: 14))
                .foregroundStyle(isActive ? .accentColor : .secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(device.name)
                    .font(.system(size: 12, weight: .medium))
                Text(device.ip)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isActive {
                Circle()
                    .fill(.green)
                    .frame(width: 7, height: 7)
            } else {
                Button("Connect") { pairing.switchTo(device) }
                    .font(.system(size: 10))
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .background(isActive ? Color.accentColor.opacity(0.06) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contextMenu {
            Button("Remove Device", role: .destructive) {
                pairing.removeDevice(device)
            }
        }
    }
}
