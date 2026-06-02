import Foundation
import CoreMedia
import CoreMediaIO
import CoreVideo

/// Implements the virtual camera device source.
/// Receives CVPixelBuffer frames from the main app (via IPC/shared memory)
/// and pushes them into the CMIOExtensionStream for macOS to consume.
final class VirtualCameraDeviceController: NSObject, CMIOExtensionDeviceSource {

    private(set) var device: CMIOExtensionDevice!
    private var videoStream: CMIOExtensionStream?
    private var streamSource: VirtualCameraStreamSource?
    private var pixelBufferPool: CVPixelBufferPool?

    // Frame dimensions
    private let frameWidth = 1920
    private let frameHeight = 1080
    private let frameRate: Int32 = 60

    // IPC socket to receive frames from main app
    private var ipcListener: CFSocket?

    // MARK: - CMIOExtensionDeviceSource

    var availableProperties: Set<CMIOExtensionProperty> {
        return [.deviceModel, .deviceTransportType]
    }

    func deviceProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionDeviceProperties {
        let props = CMIOExtensionDeviceProperties(dictionary: [:])
        if properties.contains(.deviceModel) {
            props.model = "Continuity Virtual Camera"
        }
        if properties.contains(.deviceTransportType) {
            props.transportType = kIOAudioDeviceTransportTypeVirtual
        }
        return props
    }

    func setDeviceProperties(_ deviceProperties: CMIOExtensionDeviceProperties) throws {}

    // MARK: - Stream Setup

    func setupStream() {
        let streamID = UUID(uuidString: "B2C3D4E5-F6A7-8901-BCDE-F12345678901")!

        let videoFormat = CMIOExtensionStreamFormat(
            formatDescription: createVideoFormatDescription(),
            maxFrameDuration: CMTime(value: 1, timescale: CMTimeScale(frameRate)),
            minFrameDuration: CMTime(value: 1, timescale: CMTimeScale(frameRate)),
            validFrameDurations: nil
        )

        streamSource = VirtualCameraStreamSource(
            deviceController: self,
            streamID: streamID,
            streamFormat: videoFormat
        )

        videoStream = CMIOExtensionStream(
            localizedName: "Continuity Camera Video",
            streamID: streamID,
            direction: .source,
            clockType: .hostTime,
            source: streamSource!
        )

        setupPixelBufferPool()
        startIPCListener()
    }

    // MARK: - Frame Ingestion

    /// Called by the IPC receiver when a new frame arrives from the main app.
    func receiveFramePayload(pixelBuffer: CVPixelBuffer) {
        guard let stream = videoStream else { return }

        var timingInfo = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(frameRate)),
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: .invalid
        )

        var formatDesc: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: nil,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDesc
        )

        guard let desc = formatDesc else { return }

        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: nil,
            imageBuffer: pixelBuffer,
            formatDescription: desc,
            sampleTiming: &timingInfo,
            sampleBufferOut: &sampleBuffer
        )

        if let buffer = sampleBuffer {
            stream.send(buffer, discontinuity: [], hostTimeInNanoseconds: 0)
        }
    }

    // MARK: - Pixel Buffer Pool

    private func setupPixelBufferPool() {
        let poolAttributes: [String: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey as String: 3
        ]
        let bufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: frameWidth,
            kCVPixelBufferHeightKey as String: frameHeight,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        CVPixelBufferPoolCreate(
            nil,
            poolAttributes as CFDictionary,
            bufferAttributes as CFDictionary,
            &pixelBufferPool
        )
    }

    // MARK: - IPC Listener (receives frames from main app)

    private func startIPCListener() {
        // Listen on a Unix domain socket for frame data from the main app
        // In production, use shared memory (IOSurface) for zero-copy performance
        print("[CameraExtension] IPC listener started — waiting for frames from main app.")
    }

    // MARK: - Helpers

    private func createVideoFormatDescription() -> CMVideoFormatDescription {
        var desc: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreate(
            allocator: nil,
            codecType: kCMVideoCodecType_422YpCbCr8,
            width: Int32(frameWidth),
            height: Int32(frameHeight),
            extensions: nil,
            formatDescriptionOut: &desc
        )
        return desc!
    }
}

// MARK: - Stream Source

final class VirtualCameraStreamSource: NSObject, CMIOExtensionStreamSource {
    private weak var deviceController: VirtualCameraDeviceController?
    private let streamID: UUID
    private let streamFormat: CMIOExtensionStreamFormat

    init(deviceController: VirtualCameraDeviceController, streamID: UUID, streamFormat: CMIOExtensionStreamFormat) {
        self.deviceController = deviceController
        self.streamID = streamID
        self.streamFormat = streamFormat
    }

    var formats: [CMIOExtensionStreamFormat] {
        return [streamFormat]
    }

    var activeFormatIndex: Int = 0

    var availableProperties: Set<CMIOExtensionProperty> {
        return [.streamActiveFormatIndex, .streamFrameDuration]
    }

    func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
        let props = CMIOExtensionStreamProperties(dictionary: [:])
        if properties.contains(.streamActiveFormatIndex) {
            props.activeFormatIndex = 0
        }
        if properties.contains(.streamFrameDuration) {
            props.frameDuration = CMTime(value: 1, timescale: 60)
        }
        return props
    }

    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {
        if let index = streamProperties.activeFormatIndex {
            activeFormatIndex = index
        }
    }

    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool {
        return true
    }

    func startStream() throws {
        print("[CameraExtension] Stream started.")
    }

    func stopStream() throws {
        print("[CameraExtension] Stream stopped.")
    }
}
