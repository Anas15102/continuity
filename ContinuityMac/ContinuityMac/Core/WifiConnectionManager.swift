import Foundation

/// Switches ADB from USB to Wi-Fi mode so the phone can be unplugged.
/// Phone IP on this network: 192.168.0.30
final class WifiConnectionManager: ObservableObject {
    static let shared = WifiConnectionManager()
    private init() {}

    @Published var isWifiConnected = false
    @Published var statusMessage = "USB connected"

    private let phoneIP = "192.168.0.30"
    private let adbPort = 5555

    // MARK: - Enable Wi-Fi ADB

    /// Call this while USB is still plugged in.
    /// It switches ADB to TCP mode, then connects over Wi-Fi.
    /// After this succeeds the USB cable can be unplugged.
    func enableWifiMode(completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.async { self.statusMessage = "Switching to Wi-Fi..." }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // Step 1 — tell the phone to listen on TCP port 5555
            let tcpResult = ADBBridge.shared.run(["tcpip", "\(self.adbPort)"])
            print("[WiFi] tcpip result: \(tcpResult)")
            Thread.sleep(forTimeInterval: 1.5) // give phone time to open port

            // Step 2 — connect over Wi-Fi
            let connectResult = ADBBridge.shared.run(["connect", "\(self.phoneIP):\(self.adbPort)"])
            print("[WiFi] connect result: \(connectResult)")

            let success = connectResult.contains("connected")

            DispatchQueue.main.async {
                self.isWifiConnected = success
                self.statusMessage = success
                    ? "Wi-Fi · \(self.phoneIP)"
                    : "Wi-Fi failed — stay on USB"
                completion(success)
            }
        }
    }

    /// Disconnect Wi-Fi ADB (falls back to USB if still plugged in).
    func disconnect() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }
            ADBBridge.shared.run(["disconnect", "\(self.phoneIP):\(self.adbPort)"])
            DispatchQueue.main.async {
                self.isWifiConnected = false
                self.statusMessage = "USB connected"
            }
        }
    }

    /// Check if Wi-Fi ADB is still alive (call periodically).
    func checkConnection() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }
            let devices = ADBBridge.shared.connectedDevices()
            let wifiActive = devices.contains { $0.contains(self.phoneIP) }
            DispatchQueue.main.async {
                if self.isWifiConnected && !wifiActive {
                    self.isWifiConnected = false
                    self.statusMessage = "Wi-Fi disconnected"
                }
            }
        }
    }
}
