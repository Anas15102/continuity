import Foundation
import Network

/// Discovers the Android companion app on the local network via mDNS/Bonjour.
/// Also polls ADB for USB-connected devices as a fallback.
final class DeviceDiscovery: ObservableObject {
    static let shared = DeviceDiscovery()
    private init() {}

    // MARK: - Published State

    @Published var isConnected: Bool = false
    @Published var connectedDeviceName: String? = nil
    @Published var batteryLevel: Int = 0
    @Published var deviceIP: String? = nil {
        didSet {
            // Auto-connect clipboard daemon whenever IP is resolved
            if let ip = deviceIP, ip != oldValue {
                print("[Discovery] Device IP resolved: \(ip) — connecting clipboard…")
                ClipboardSyncDaemon.shared.connectToAndroid(ip: ip)
            }
        }
    }

    // MARK: - Private

    private var browser: NWBrowser?
    private var adbPollTimer: Timer?
    private let serviceType = "_continuity._tcp"

    // MARK: - Start / Stop

    func startBrowsing() {
        startMDNSBrowsing()
        startADBPolling()
    }

    func stopBrowsing() {
        browser?.cancel()
        adbPollTimer?.invalidate()
    }

    // MARK: - mDNS Browser

    private func startMDNSBrowsing() {
        let params = NWParameters()
        params.includePeerToPeer = true

        let descriptor = NWBrowser.Descriptor.bonjour(type: serviceType, domain: "local.")
        browser = NWBrowser(for: descriptor, using: params)

        browser?.stateUpdateHandler = { state in
            switch state {
            case .ready:   print("[Discovery] mDNS browser ready.")
            case .failed(let e): print("[Discovery] mDNS browser failed: \(e)")
            default: break
            }
        }

        browser?.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self = self else { return }
            if let result = results.first {
                self.resolveService(result)
            }
        }

        browser?.start(queue: .global(qos: .background))
    }

    private func resolveService(_ result: NWBrowser.Result) {
        // Extract endpoint info
        switch result.endpoint {
        case .service(let name, let type, let domain, _):
            print("[Discovery] Found companion: \(name)")
            DispatchQueue.main.async {
                self.isConnected = true
                self.connectedDeviceName = name
            }
            // Resolve the actual IP using NWConnection
            resolveIP(name: name, type: type, domain: domain)
        default:
            break
        }
    }

    private func resolveIP(name: String, type: String, domain: String) {
        let endpoint = NWEndpoint.service(name: name, type: type, domain: domain, interface: nil)
        let conn = NWConnection(to: endpoint, using: .tcp)

        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                // Extract resolved IP from the connection path
                if let innerEndpoint = conn.currentPath?.remoteEndpoint,
                   case .hostPort(let host, _) = innerEndpoint {
                    let ip = "\(host)".components(separatedBy: "%").first ?? "\(host)"
                    DispatchQueue.main.async {
                        self?.deviceIP = ip
                        print("[Discovery] Resolved IP: \(ip)")
                    }
                }
                conn.cancel()
            case .failed:
                conn.cancel()
            default:
                break
            }
        }
        conn.start(queue: .global(qos: .background))
    }

    // MARK: - ADB Polling (USB fallback)

    private func startADBPolling() {
        adbPollTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            self?.pollADB()
        }
        adbPollTimer?.fire()
    }

    private func pollADB() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }
            let devices = ADBBridge.shared.connectedDevices()
            guard !devices.isEmpty else {
                // Only clear if we don't have a Wi-Fi connection
                DispatchQueue.main.async {
                    if self.deviceIP == nil {
                        self.isConnected = false
                        self.connectedDeviceName = nil
                    }
                }
                return
            }

            let model = ADBBridge.shared.deviceModel()
            let battery = ADBBridge.shared.batteryLevel()
            let ip = ADBBridge.shared.deviceWifiIP()

            DispatchQueue.main.async {
                self.isConnected = true
                self.connectedDeviceName = model.isEmpty ? "Android Device" : model
                self.batteryLevel = battery
                // Only set IP from ADB if mDNS hasn't resolved one yet
                if self.deviceIP == nil, let ip = ip {
                    self.deviceIP = ip
                }
            }
        }
    }
}
