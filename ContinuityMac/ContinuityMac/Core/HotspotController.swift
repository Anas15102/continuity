import Foundation

/// Controls the Android device's mobile hotspot via ADB shell commands.
final class HotspotController: ObservableObject {
    static let shared = HotspotController()
    private init() {}

    // MARK: - Published State

    @Published var isActive = false

    // MARK: - Toggle

    func toggle() {
        if isActive {
            disable()
        } else {
            enable()
        }
    }

    func enable() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Method 1: Open tethering settings UI
            ADBBridge.shared.shell("am start -n com.android.settings/.TetherSettings")

            // Method 2: Direct connectivity service call (may require root on some devices)
            // ADBBridge.shared.shell("service call connectivity 30 i32 1")

            DispatchQueue.main.async {
                self?.isActive = true
                print("[Hotspot] Enabled.")
            }
        }
    }

    func disable() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            ADBBridge.shared.shell("service call connectivity 30 i32 0")
            DispatchQueue.main.async {
                self?.isActive = false
                print("[Hotspot] Disabled.")
            }
        }
    }

    /// Checks current tethering state from dumpsys.
    func refreshState() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            let output = ADBBridge.shared.shell("dumpsys connectivity | grep -i tether")
            let active = output.lowercased().contains("enabled") || output.contains("tethering")
            DispatchQueue.main.async {
                self?.isActive = active
            }
        }
    }
}
