import Foundation
import SwiftUI

enum MirroringMode {
    case mirror
    case appStream
    case desktop
}

/// Manages scrcpy mirroring sessions.
final class MirroringSessionManager: ObservableObject {
    static let shared = MirroringSessionManager()
    private init() {}

    // MARK: - Published State
    @Published var isMirrorActive = false
    @Published var isAppStreamActive = false
    @Published var isDesktopModeActive = false
    @Published var installedApps: [AndroidApp] = []

    // MARK: - Private
    private var scrcpyProcess: Process?

    private var scrcpyPath: String {
        Bundle.main.path(forResource: "scrcpy", ofType: nil)
            ?? "/opt/homebrew/bin/scrcpy"
    }

    // MARK: - Session Control

    func establishMirroringSession(mode: MirroringMode, appPackage: String? = nil) {
        terminateMirroringSession()

        // For desktop mode, enable it via ADB first
        if mode == .desktop {
            enableDesktopMode()
        }

        let args = buildArguments(for: mode, appPackage: appPackage)
        print("[Mirror] scrcpy \(args.joined(separator: " "))")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: scrcpyPath)
        process.arguments = args

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        process.environment = env

        scrcpyProcess = process

        do {
            try process.run()
            DispatchQueue.main.async {
                switch mode {
                case .mirror:    self.isMirrorActive = true
                case .appStream: self.isAppStreamActive = true
                case .desktop:   self.isDesktopModeActive = true
                }
            }
            process.terminationHandler = { [weak self] _ in
                DispatchQueue.main.async {
                    self?.isMirrorActive = false
                    self?.isAppStreamActive = false
                    self?.isDesktopModeActive = false
                    self?.scrcpyProcess = nil
                }
            }
        } catch {
            print("[Mirror] Failed to launch scrcpy: \(error)")
        }
    }

    func terminateMirroringSession() {
        scrcpyProcess?.terminate()
        scrcpyProcess = nil
        isMirrorActive = false
        isAppStreamActive = false
        isDesktopModeActive = false
    }

    // MARK: - Desktop Mode Enable

    /// Enables Android desktop mode via ADB settings.
    /// Required on Android 10+ before scrcpy --new-display works properly.
    private func enableDesktopMode() {
        // Enable freeform windows
        ADBBridge.shared.shell("settings put global enable_freeform_support 1")
        ADBBridge.shared.shell("settings put global force_desktop_mode_on_external_displays 1")
        // Enable desktop mode on Motorola Edge 50 Pro (Android 16)
        ADBBridge.shared.shell("settings put secure desktop_mode_on 1")
        ADBBridge.shared.shell("cmd window set-multi-window-config --supportsMultiWindow=true")
        print("[Mirror] Desktop mode settings applied.")
    }

    // MARK: - App List

    /// Fetches all installed user apps from the device.
    func fetchInstalledApps() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Get all non-system packages
            let output = ADBBridge.shared.shell("pm list packages -3")
            // Output: "package:com.whatsapp\npackage:com.instagram.android\n..."
            let packages = output
                .components(separatedBy: "\n")
                .compactMap { line -> String? in
                    let pkg = line.replacingOccurrences(of: "package:", with: "").trimmingCharacters(in: .whitespaces)
                    return pkg.isEmpty ? nil : pkg
                }

            // Get friendly names for each package
            var apps: [AndroidApp] = []
            for pkg in packages {
                let label = ADBBridge.shared.shell(
                    "cmd package resolve-activity --brief -c android.intent.category.LAUNCHER \(pkg) 2>/dev/null | tail -1"
                )
                let name = label.isEmpty ? pkg.components(separatedBy: ".").last?.capitalized ?? pkg : label
                apps.append(AndroidApp(packageName: pkg, displayName: name))
            }

            // Sort alphabetically
            apps.sort { $0.displayName < $1.displayName }

            DispatchQueue.main.async {
                self?.installedApps = apps
                print("[Mirror] Found \(apps.count) installed apps.")
            }
        }
    }

    /// Launches a specific app in a virtual display window (App Streaming).
    func streamApp(package: String) {
        terminateMirroringSession()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: scrcpyPath)
        // New display + launch specific app
        process.arguments = [
            "--video-codec=h265",
            "--max-fps=60",
            "--new-display=1080x1920/420",
            "--stay-awake",
            "--keyboard=uhid",
            "--start-app=\(package)"
        ]

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        process.environment = env

        scrcpyProcess = process
        do {
            try process.run()
            DispatchQueue.main.async { self.isAppStreamActive = true }
            process.terminationHandler = { [weak self] _ in
                DispatchQueue.main.async { self?.isAppStreamActive = false }
            }
        } catch {
            print("[Mirror] streamApp failed: \(error)")
        }
    }

    // MARK: - Argument Builder

    private func buildArguments(for mode: MirroringMode, appPackage: String?) -> [String] {
        switch mode {
        case .mirror:
            return [
                "--video-codec=h265",
                "--max-size=1920",
                "--max-fps=60",
                "--turn-screen-off",
                "--stay-awake",
                "--keyboard=uhid",
                "--audio-codec=aac"
            ]
        case .appStream:
            var args = [
                "--video-codec=h265",
                "--max-fps=60",
                "--new-display=1080x1920/420",
                "--stay-awake",
                "--keyboard=uhid"
            ]
            if let pkg = appPackage {
                args.append("--start-app=\(pkg)")
            }
            return args
        case .desktop:
            // Full desktop mode for Android 16 / Motorola Edge 50 Pro
            // --no-vd-destroy-content keeps apps alive when display is removed
            // DPI 240 matches tablet-class layout on 1920x1080
            return [
                "--video-codec=h265",
                "--max-fps=60",
                "--new-display=1920x1080/240",
                "--no-vd-system-decorations",
                "--no-vd-destroy-content",
                "--stay-awake",
                "--keyboard=uhid",
                "--audio-codec=aac"
            ]
        }
    }
}

// MARK: - Model

struct AndroidApp: Identifiable {
    let id = UUID()
    let packageName: String
    let displayName: String
}
