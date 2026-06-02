import Foundation

/// Manages the scrcpy camera capture process that feeds frames
/// into the CMIOExtension virtual camera device.
final class VirtualCameraController: ObservableObject {
    static let shared = VirtualCameraController()
    private init() {}

    // MARK: - Published State

    @Published var isCameraActive = false

    // MARK: - Private

    private var cameraProcess: Process?

    private var scrcpyPath: String {
        Bundle.main.path(forResource: "scrcpy", ofType: nil)
            ?? "/opt/homebrew/bin/scrcpy"
    }

    // MARK: - Camera Control

    /// Starts capturing the phone's back camera and routing frames to the virtual camera.
    func startCamera(facing: CameraFacing = .back, resolution: String = "1920x1080", fps: Int = 60) {
        stopCamera()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: scrcpyPath)
        process.arguments = [
            "--video-source=camera",
            "--camera-facing=\(facing.rawValue)",
            "--camera-size=\(resolution)",
            "--camera-fps=\(fps)",
            "--no-playback",          // Don't show preview window — pipe to extension
            "--v4l2-sink=/dev/video0" // On Linux; on macOS frames go via IPC to extension
        ]

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        process.environment = env

        cameraProcess = process

        do {
            try process.run()
            DispatchQueue.main.async { self.isCameraActive = true }

            process.terminationHandler = { [weak self] _ in
                DispatchQueue.main.async {
                    self?.isCameraActive = false
                    self?.cameraProcess = nil
                    print("[Camera] Camera session ended.")
                }
            }
            print("[Camera] Camera capture started (\(facing.rawValue), \(resolution) @ \(fps)fps)")
        } catch {
            print("[Camera] Failed to start camera: \(error)")
        }
    }

    func stopCamera() {
        cameraProcess?.terminate()
        cameraProcess = nil
        isCameraActive = false
    }
}

// MARK: - Camera Facing

enum CameraFacing: String {
    case back = "back"
    case front = "front"
}
