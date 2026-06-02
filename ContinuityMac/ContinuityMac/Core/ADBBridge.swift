import Foundation

/// Central wrapper around the embedded `adb` binary.
/// All ADB interactions go through this class.
final class ADBBridge {
    static let shared = ADBBridge()
    private init() {}

    // MARK: - Binary Path

    /// Resolves the embedded adb binary from the app bundle.
    var adbPath: String {
        if let path = Bundle.main.path(forResource: "adb", ofType: nil) {
            return path
        }
        // Fallback to system adb (useful during development)
        return "/opt/homebrew/bin/adb"
    }

    // MARK: - Core Run Methods

    /// Runs an adb command synchronously and returns stdout output.
    @discardableResult
    func run(_ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: adbPath)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            print("[ADB] Failed to run: \(arguments.joined(separator: " ")) — \(error)")
            return ""
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Runs an adb shell command synchronously.
    @discardableResult
    func shell(_ command: String) -> String {
        return run(["shell", command])
    }

    /// Runs an adb command asynchronously with a completion handler.
    func runAsync(_ arguments: [String], completion: @escaping (String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.run(arguments)
            DispatchQueue.main.async { completion(result) }
        }
    }

    // MARK: - Device Management

    /// Returns list of connected device serials.
    func connectedDevices() -> [String] {
        let output = run(["devices"])
        return output
            .components(separatedBy: "\n")
            .dropFirst()  // skip "List of devices attached" header
            .compactMap { line -> String? in
                let parts = line.components(separatedBy: "\t")
                guard parts.count == 2, parts[1].trimmingCharacters(in: .whitespaces) == "device" else {
                    return nil
                }
                return parts[0].trimmingCharacters(in: .whitespaces)
            }
    }

    /// Connects to a device over TCP/IP (Wi-Fi ADB).
    func connectWifi(ip: String, port: Int = 5555) -> Bool {
        let result = run(["connect", "\(ip):\(port)"])
        return result.contains("connected")
    }

    /// Switches ADB to TCP/IP mode on the given port (must be connected via USB first).
    func enableTcpip(port: Int = 5555) {
        run(["tcpip", "\(port)"])
    }

    // MARK: - Device Info

    /// Returns the device model name.
    func deviceModel() -> String {
        return shell("getprop ro.product.model")
    }

    /// Returns battery level as an integer 0–100.
    func batteryLevel() -> Int {
        let output = shell("dumpsys battery | grep level")
        // Output: "  level: 87"
        if let match = output.range(of: #"\d+"#, options: .regularExpression) {
            return Int(output[match]) ?? 0
        }
        return 0
    }

    /// Returns the device's Wi-Fi IP address.
    func deviceWifiIP() -> String? {
        let output = shell("ip route | grep wlan0")
        // Parse "src <ip>" from route output
        if let srcRange = output.range(of: "src ") {
            let after = output[srcRange.upperBound...]
            let ip = after.components(separatedBy: " ").first ?? ""
            return ip.isEmpty ? nil : ip
        }
        return nil
    }

    // MARK: - File Transfer

    /// Pushes a local file to the device's Downloads folder.
    func pushFile(localPath: String, remotePath: String = "/sdcard/Download/") -> Bool {
        let result = run(["push", localPath, remotePath])
        return result.contains("pushed") || result.contains("1 file")
    }

    // MARK: - Input Events

    /// Sends a tap event at the given Android screen coordinates.
    func sendTap(x: Int, y: Int) {
        shell("input tap \(x) \(y)")
    }

    /// Sends a mouse move event (relative delta).
    func sendMouseMove(x: Int, y: Int) {
        shell("input mouse move \(x) \(y)")
    }

    /// Sends a key event using Android KeyEvent code.
    func sendKeyEvent(keyCode: Int) {
        shell("input keyevent \(keyCode)")
    }

    // MARK: - Hotspot

    /// Enables mobile hotspot via settings intent.
    func enableHotspot() {
        shell("am start -n com.android.settings/.TetherSettings")
    }

    /// Toggles tethering via connectivity service call.
    func setTethering(enabled: Bool) {
        let flag = enabled ? 1 : 0
        shell("service call connectivity 30 i32 \(flag)")
    }
}
