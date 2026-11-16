import CoreMediaIO
import Foundation
import IOKit.audio
import os.log
import VanishCore

private let log = Logger(subsystem: "com.vanishcam.Vanish.CameraExtension", category: "extension")

/// Custom property published on the device: who is watching the source stream.
let clientsProperty = CMIOExtensionProperty(rawValue: "4cc_\(VanishConstants.clientsPropertyFourCC)_glob_0000")

// MARK: - Provider

final class ExtensionProviderSource: NSObject, CMIOExtensionProviderSource {
    private(set) var provider: CMIOExtensionProvider!
    private var deviceSource: ExtensionDeviceSource!

    init(clientQueue: DispatchQueue?) {
        super.init()
        provider = CMIOExtensionProvider(source: self, clientQueue: clientQueue)
        deviceSource = ExtensionDeviceSource()
        do {
            try provider.addDevice(deviceSource.device)
        } catch {
            fatalError("Failed to add device: \(error.localizedDescription)")
        }
    }

    func connect(to client: CMIOExtensionClient) throws {}
    func disconnect(from client: CMIOExtensionClient) {}

    var availableProperties: Set<CMIOExtensionProperty> { [.providerManufacturer] }

    func providerProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionProviderProperties {
        let props = CMIOExtensionProviderProperties(dictionary: [:])
        if properties.contains(.providerManufacturer) {
            props.manufacturer = VanishConstants.manufacturer
        }
        return props
    }

    func setProviderProperties(_ providerProperties: CMIOExtensionProviderProperties) throws {}
}

// MARK: - Device

/// One virtual camera with two streams:
/// - source: what call apps read
/// - sink: where Vanish.app pushes rendered frames
/// A 30 fps timer drives the source; it forwards the newest sink frame, or the stub when frames are stale.
final class ExtensionDeviceSource: NSObject, CMIOExtensionDeviceSource {
    private(set) var device: CMIOExtensionDevice!
    private var sourceStream: SourceStream!
    private var sinkStream: SinkStream!

    private let queue = DispatchQueue(label: "vanish.extension.frames", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private var formatDescription: CMFormatDescription!
    private var stub: CVPixelBuffer?

    // Guarded by `queue`.
    private var latestFrame: CVPixelBuffer?
    private var watchdog = FrameWatchdog(timeout: VanishConstants.staleTimeout)
    private var sourceClients: [UUID: String] = [:]
    private var lastClientSigningID: String?

    override init() {
        super.init()
        device = CMIOExtensionDevice(localizedName: VanishConstants.deviceName,
                                     deviceID: VanishConstants.deviceID,
                                     legacyDeviceID: VanishConstants.deviceID.uuidString,
                                     source: self)

        CMVideoFormatDescriptionCreate(allocator: kCFAllocatorDefault,
                                       codecType: VanishConstants.pixelFormat,
                                       width: VanishConstants.width,
                                       height: VanishConstants.height,
                                       extensions: nil,
                                       formatDescriptionOut: &formatDescription)
        let frameDuration = CMTime(value: 1, timescale: VanishConstants.fps)
        let format = CMIOExtensionStreamFormat(formatDescription: formatDescription,
                                               maxFrameDuration: frameDuration,
                                               minFrameDuration: frameDuration,
                                               validFrameDurations: nil)

        sourceStream = SourceStream(format: format, owner: self)
        sinkStream = SinkStream(format: format, owner: self)
        stub = StubFrame.make(width: Int(VanishConstants.width), height: Int(VanishConstants.height))

        do {
            try device.addStream(sourceStream.stream)
            try device.addStream(sinkStream.stream)
        } catch {
            fatalError("Failed to add streams: \(error.localizedDescription)")
        }
    }

    // MARK: Device properties

    var availableProperties: Set<CMIOExtensionProperty> {
        [.deviceTransportType, .deviceModel, clientsProperty]
    }

    func deviceProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionDeviceProperties {
        let props = CMIOExtensionDeviceProperties(dictionary: [:])
        if properties.contains(.deviceTransportType) {
            props.transportType = kIOAudioDeviceTransportTypeVirtual
        }
        if properties.contains(.deviceModel) {
            props.model = VanishConstants.deviceModel
        }
        if properties.contains(clientsProperty) {
            let info = queue.sync { ClientInfo(count: sourceClients.count, signingID: lastClientSigningID) }
            props.setPropertyState(CMIOExtensionPropertyState(value: info.encoded as NSString), forProperty: clientsProperty)
        }
        return props
    }

    func setDeviceProperties(_ deviceProperties: CMIOExtensionDeviceProperties) throws {}

    // MARK: Source lifecycle

    fileprivate func sourceStarted(client: CMIOExtensionClient?) {
        queue.sync {
            let id = client?.clientID ?? UUID()
            sourceClients[id] = client?.signingID ?? ""
            if let s = client?.signingID, !s.isEmpty { lastClientSigningID = s }
            if timer == nil { startTimer() }
        }
        publishClients()
    }

    fileprivate func sourceStopped(client: CMIOExtensionClient?) {
        queue.sync {
            if let id = client?.clientID {
                sourceClients[id] = nil
            } else {
                sourceClients.removeAll()
            }
            if sourceClients.isEmpty {
                timer?.cancel()
                timer = nil
                lastClientSigningID = nil
            } else {
                lastClientSigningID = sourceClients.values.first(where: { !$0.isEmpty })
            }
        }
        publishClients()
    }

    private func publishClients() {
        let info = queue.sync { ClientInfo(count: sourceClients.count, signingID: lastClientSigningID) }
        device.notifyPropertiesChanged([clientsProperty: CMIOExtensionPropertyState(value: info.encoded as NSString as AnyObject)])
    }

    private func startTimer() {
        let t = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        t.schedule(deadline: .now(), repeating: 1.0 / Double(VanishConstants.fps), leeway: .milliseconds(1))
        t.setEventHandler { [weak self] in self?.emitFrame() }
        t.resume()
        timer = t
    }

    /// Runs on `queue`.
    private func emitFrame() {
        let nowTime = CMClockGetTime(CMClockGetHostTimeClock())
        let frame: CVPixelBuffer?
        if watchdog.isStale(now: nowTime.seconds) {
            frame = stub
        } else {
            frame = latestFrame
        }
        guard let pixelBuffer = frame else { return }

        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: VanishConstants.fps),
                                        presentationTimeStamp: nowTime,
                                        decodeTimeStamp: .invalid)
        var sampleBuffer: CMSampleBuffer?
        let err = CMSampleBufferCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                     imageBuffer: pixelBuffer,
                                                     dataReady: true,
                                                     makeDataReadyCallback: nil,
                                                     refcon: nil,
                                                     formatDescription: formatDescription,
                                                     sampleTiming: &timing,
                                                     sampleBufferOut: &sampleBuffer)
        guard err == noErr, let sampleBuffer else { return }
        sourceStream.stream.send(sampleBuffer,
                                 discontinuity: [],
                                 hostTimeInNanoseconds: UInt64(nowTime.seconds * Double(NSEC_PER_SEC)))
    }

    // MARK: Sink

    fileprivate func receive(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        guard CVPixelBufferGetWidth(pixelBuffer) == Int(VanishConstants.width),
              CVPixelBufferGetHeight(pixelBuffer) == Int(VanishConstants.height) else {
            log.error("Dropping sink frame with unexpected size")
            return
        }
        let now = CMClockGetTime(CMClockGetHostTimeClock()).seconds
        queue.async {
            self.latestFrame = pixelBuffer
            self.watchdog.frameArrived(at: now)
        }
    }
}

// MARK: - Streams

final class SourceStream: NSObject, CMIOExtensionStreamSource {
    private(set) var stream: CMIOExtensionStream!
    private let format: CMIOExtensionStreamFormat
    private unowned let owner: ExtensionDeviceSource
    private var currentClient: CMIOExtensionClient?

    init(format: CMIOExtensionStreamFormat, owner: ExtensionDeviceSource) {
        self.format = format
        self.owner = owner
        super.init()
        stream = CMIOExtensionStream(localizedName: VanishConstants.sourceStreamName,
                                     streamID: VanishConstants.sourceStreamID,
                                     direction: .source,
                                     clockType: .hostTime,
                                     source: self)
    }

    var formats: [CMIOExtensionStreamFormat] { [format] }

    var availableProperties: Set<CMIOExtensionProperty> { [.streamActiveFormatIndex, .streamFrameDuration] }

    func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
        let props = CMIOExtensionStreamProperties(dictionary: [:])
        if properties.contains(.streamActiveFormatIndex) { props.activeFormatIndex = 0 }
        if properties.contains(.streamFrameDuration) {
            props.frameDuration = CMTime(value: 1, timescale: VanishConstants.fps)
        }
        return props
    }

    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {}

    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool {
        currentClient = client
        return true
    }

    func startStream() throws {
        owner.sourceStarted(client: currentClient)
    }

    func stopStream() throws {
        owner.sourceStopped(client: currentClient)
    }
}

final class SinkStream: NSObject, CMIOExtensionStreamSource {
    private(set) var stream: CMIOExtensionStream!
    private let format: CMIOExtensionStreamFormat
    private unowned let owner: ExtensionDeviceSource
    private var client: CMIOExtensionClient?
    private var running = false

    init(format: CMIOExtensionStreamFormat, owner: ExtensionDeviceSource) {
        self.format = format
        self.owner = owner
        super.init()
        stream = CMIOExtensionStream(localizedName: VanishConstants.sinkStreamName,
                                     streamID: VanishConstants.sinkStreamID,
                                     direction: .sink,
                                     clockType: .hostTime,
                                     source: self)
    }

    var formats: [CMIOExtensionStreamFormat] { [format] }

    var availableProperties: Set<CMIOExtensionProperty> {
        [.streamActiveFormatIndex, .streamFrameDuration, .streamSinkBufferQueueSize,
         .streamSinkBuffersRequiredForStartup, .streamSinkBufferUnderrunCount, .streamSinkEndOfData]
    }

    func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
        let props = CMIOExtensionStreamProperties(dictionary: [:])
        if properties.contains(.streamActiveFormatIndex) { props.activeFormatIndex = 0 }
        if properties.contains(.streamFrameDuration) {
            props.frameDuration = CMTime(value: 1, timescale: VanishConstants.fps)
        }
        if properties.contains(.streamSinkBufferQueueSize) { props.sinkBufferQueueSize = 1 }
        if properties.contains(.streamSinkBuffersRequiredForStartup) { props.sinkBuffersRequiredForStartup = 1 }
        return props
    }

    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {}

    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool {
        self.client = client
        return true
    }

    func startStream() throws {
        running = true
        consumeNext()
    }

    func stopStream() throws {
        running = false
    }

    private func consumeNext() {
        guard running, let client else { return }
        stream.consumeSampleBuffer(from: client) { [weak self] sampleBuffer, sequenceNumber, _, _, error in
            guard let self else { return }
            if let sampleBuffer {
                self.owner.receive(sampleBuffer)
                let output = CMIOExtensionScheduledOutput(
                    sequenceNumber: sequenceNumber,
                    hostTimeInNanoseconds: UInt64(CMClockGetTime(CMClockGetHostTimeClock()).seconds * Double(NSEC_PER_SEC)))
                self.stream.notifyScheduledOutputChanged(output)
            } else if let error {
                log.debug("Sink consume error: \(error.localizedDescription, privacy: .public)")
            }
            // Keep pulling; a short delay on error avoids a hot loop when no client is feeding.
            if sampleBuffer == nil {
                DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + .milliseconds(10)) { self.consumeNext() }
            } else {
                self.consumeNext()
            }
        }
    }
}
