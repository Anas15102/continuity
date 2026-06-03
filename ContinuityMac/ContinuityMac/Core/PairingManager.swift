import Foundation
import SwiftUI
import Network

/// Stores paired devices and auto-connects on launch.
/// Pairing flow:
///   1. User clicks "Pair New Device" on Mac
///   2. QR scanner window opens
///   3. User scans QR from Android app
///   4. Mac saves IP+name to UserDefaults
///   5. On next launch, Mac auto-connects to all saved devices
final class PairingManager: ObservableObject {
    static let shared = PairingManager()
    private init() { loadDevices() }

    // MARK: - Published

    @Published var pairedDevices: [PairedDevice] = []
    @Published var activeDeviceID: UUID? = nil
    @Published var showQRScanner = false
    @Published var showPairingSheet = false

    // MARK: - Persistence key
    private let storageKey = "com.continuity.pairedDevices"

    // MARK: - Auto-connect on launch

    func autoConnect() {
        guard !pairedDevices.isEmpty else {
            print("[Pairing] No saved devices.")
            return
        }
        // Try connecting to each saved device; use the first that responds
        for device in pairedDevices {
            print("[Pairing] Auto-connecting to \(device.name) at \(device.ip):\(device.port)")
            ClipboardSyncDaemon.shared.connectToAndroid(ip: device.ip)
            DispatchQueue.main.async {
                self.activeDeviceID = device.id
                DeviceDiscovery.shared.setManualDevice(name: device.name, ip: device.ip)
            }
            break // connect to first saved device; user can switch manually
        }
    }

    // MARK: - Pair from QR

    /// Called after QR code is scanned. URL format: continuity://pair?ip=X&port=9876&name=Pixel8
    func pairFromURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString),
              url.scheme == "continuity",
              url.host == "pair" else { return false }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard let ip = components?.queryItems?.first(where: { $0.name == "ip" })?.value,
              let portStr = components?.queryItems?.first(where: { $0.name == "port" })?.value,
              let port = Int(portStr) else { return false }

        let name = components?.queryItems?.first(where: { $0.name == "name" })?.value ?? "Android Device"

        let device = PairedDevice(name: name, ip: ip, port: port)
        addDevice(device)

        // Connect immediately
        ClipboardSyncDaemon.shared.connectToAndroid(ip: ip)
        DispatchQueue.main.async {
            self.activeDeviceID = device.id
            DeviceDiscovery.shared.setManualDevice(name: name, ip: ip)
            self.showQRScanner = false
        }

        print("[Pairing] Paired \(name) at \(ip):\(port)")
        return true
    }

    /// Pair directly from IP (manual entry fallback)
    func pairFromIP(_ ip: String, name: String = "Android Device", port: Int = 9876) {
        let device = PairedDevice(name: name, ip: ip, port: port)
        addDevice(device)
        ClipboardSyncDaemon.shared.connectToAndroid(ip: ip)
        DispatchQueue.main.async {
            self.activeDeviceID = device.id
            DeviceDiscovery.shared.setManualDevice(name: name, ip: ip)
        }
    }

    // MARK: - Switch device

    func switchTo(_ device: PairedDevice) {
        activeDeviceID = device.id
        ClipboardSyncDaemon.shared.connectToAndroid(ip: device.ip)
        DeviceDiscovery.shared.setManualDevice(name: device.name, ip: device.ip)
        print("[Pairing] Switched to \(device.name)")
    }

    // MARK: - Remove device

    func removeDevice(_ device: PairedDevice) {
        pairedDevices.removeAll { $0.id == device.id }
        if activeDeviceID == device.id { activeDeviceID = nil }
        saveDevices()
    }

    // MARK: - Persistence

    private func addDevice(_ device: PairedDevice) {
        // Replace if same IP already saved
        pairedDevices.removeAll { $0.ip == device.ip }
        pairedDevices.insert(device, at: 0)
        saveDevices()
    }

    private func saveDevices() {
        if let data = try? JSONEncoder().encode(pairedDevices) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadDevices() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let devices = try? JSONDecoder().decode([PairedDevice].self, from: data) else { return }
        pairedDevices = devices
        print("[Pairing] Loaded \(devices.count) saved device(s)")
    }
}

// MARK: - Model

struct PairedDevice: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var ip: String
    var port: Int
    var lastSeen: Date

    init(name: String, ip: String, port: Int = 9876) {
        self.id = UUID()
        self.name = name
        self.ip = ip
        self.port = port
        self.lastSeen = Date()
    }
}
