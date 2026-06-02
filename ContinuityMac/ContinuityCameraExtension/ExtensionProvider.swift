import Foundation
import CoreMediaIO

/// Entry point for the CMIOExtension system extension.
/// Registers the virtual camera device with macOS so it appears
/// in FaceTime, Zoom, OBS, and any other video capture app.
@main
final class ExtensionProvider: NSObject, CMIOExtensionProviderSource {

    private(set) var provider: CMIOExtensionProvider!
    private var deviceController: VirtualCameraDeviceController?

    // MARK: - Init

    override init() {
        super.init()
        provider = CMIOExtensionProvider(source: self, clientQueue: nil)

        // Create and add the virtual camera device
        let deviceID = UUID(uuidString: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890")!
        let device = CMIOExtensionDevice(
            localizedName: "Continuity Camera",
            deviceID: deviceID,
            legacyDeviceID: nil,
            source: VirtualCameraDeviceController()
        )

        do {
            try provider.addDevice(device)
            print("[CameraExtension] Virtual camera device registered.")
        } catch {
            print("[CameraExtension] Failed to add device: \(error)")
        }
    }

    // MARK: - CMIOExtensionProviderSource

    func connect(to client: CMIOExtensionClient) throws {
        print("[CameraExtension] Client connected: \(client)")
    }

    func disconnect(from client: CMIOExtensionClient) {
        print("[CameraExtension] Client disconnected: \(client)")
    }

    var availableProperties: Set<CMIOExtensionProperty> {
        return [.providerName, .providerManufacturer]
    }

    func providerProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionProviderProperties {
        let props = CMIOExtensionProviderProperties(dictionary: [:])
        if properties.contains(.providerName) {
            props.name = "Continuity Camera Provider"
        }
        if properties.contains(.providerManufacturer) {
            props.manufacturer = "Continuity Suite"
        }
        return props
    }

    func setProviderProperties(_ providerProperties: CMIOExtensionProviderProperties) throws {}
}
