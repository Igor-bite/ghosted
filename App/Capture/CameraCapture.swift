import AVFoundation
import CoreMedia
import os.log

private let log = Logger(subsystem: "com.vanishcam.Vanish", category: "capture")

struct CameraInfo: Identifiable, Hashable {
    let id: String   // AVCaptureDevice.uniqueID
    let name: String
}

/// Physical camera capture. Delivers BGRA frames on `frameQueue`.
final class CameraCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let frameQueue = DispatchQueue(label: "vanish.capture.frames", qos: .userInteractive)
    var onFrame: ((CVPixelBuffer, CMTime) -> Void)?
    var onDevicesChanged: (() -> Void)?

    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "vanish.capture.session")
    private var input: AVCaptureDeviceInput?
    private(set) var currentDevice: AVCaptureDevice?
    private var observers: [NSObjectProtocol] = []

    override init() {
        super.init()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: frameQueue)
        if session.canAddOutput(output) { session.addOutput(output) }

        // Keep Center Stage from reframing the shot (it would invalidate the room snapshot).
        AVCaptureDevice.centerStageControlMode = .app
        AVCaptureDevice.isCenterStageEnabled = false

        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: AVCaptureDevice.wasDisconnectedNotification, object: nil, queue: .main) { [weak self] note in
            guard let self else { return }
            self.onDevicesChanged?()
            if let dev = note.object as? AVCaptureDevice, dev.uniqueID == self.currentDevice?.uniqueID {
                log.info("Active camera disconnected, falling back to default")
                self.select(uniqueID: nil)
            }
        })
        observers.append(nc.addObserver(forName: AVCaptureDevice.wasConnectedNotification, object: nil, queue: .main) { [weak self] _ in
            self?.onDevicesChanged?()
        })
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    // MARK: Devices

    static func availableDevices() -> [AVCaptureDevice] {
        var types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]
        if #available(macOS 14.0, *) {
            types += [.external, .continuityCamera]
        } else {
            types += [.externalUnknown]
        }
        return AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: .unspecified)
            .devices
            .filter { !isVanishCamera($0) }
    }

    static func isVanishCamera(_ d: AVCaptureDevice) -> Bool {
        d.localizedName == VanishConstants.deviceName || d.modelID == VanishConstants.deviceModel
            || d.uniqueID == VanishConstants.deviceID.uuidString
    }

    static func cameraList() -> [CameraInfo] {
        availableDevices().map { CameraInfo(id: $0.uniqueID, name: $0.localizedName) }
    }

    /// Select a camera by uniqueID (nil = system default / first available).
    func select(uniqueID: String?) {
        sessionQueue.async { [self] in
            let devices = Self.availableDevices()
            let device = devices.first { $0.uniqueID == uniqueID }
                ?? AVCaptureDevice.default(for: .video).flatMap { Self.isVanishCamera($0) ? nil : $0 }
                ?? devices.first
            guard let device, device.uniqueID != currentDevice?.uniqueID || input == nil else { return }
            session.beginConfiguration()
            if let input { session.removeInput(input) }
            input = nil
            do {
                let newInput = try AVCaptureDeviceInput(device: device)
                if session.canAddInput(newInput) {
                    session.addInput(newInput)
                    input = newInput
                    currentDevice = device
                }
            } catch {
                log.error("Cannot open camera \(device.localizedName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
            if session.canSetSessionPreset(.hd1280x720) {
                session.sessionPreset = .hd1280x720
            } else {
                session.sessionPreset = .high
            }
            session.commitConfiguration()
        }
    }

    var currentDeviceID: String? { currentDevice?.uniqueID }

    // MARK: Running

    func start() {
        sessionQueue.async { [self] in
            if input == nil { selectSync() }
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        sessionQueue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func selectSync() {
        let device = AVCaptureDevice.default(for: .video).flatMap { Self.isVanishCamera($0) ? nil : $0 }
            ?? Self.availableDevices().first
        guard let device, let newInput = try? AVCaptureDeviceInput(device: device) else { return }
        session.beginConfiguration()
        if session.canAddInput(newInput) {
            session.addInput(newInput)
            input = newInput
            currentDevice = device
        }
        if session.canSetSessionPreset(.hd1280x720) { session.sessionPreset = .hd1280x720 }
        session.commitConfiguration()
    }

    /// Lock exposure & white balance (best effort) so the room snapshot keeps matching the live frame.
    func setAutoAdjustmentsLocked(_ locked: Bool) {
        sessionQueue.async { [self] in
            guard let device = currentDevice else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                if locked {
                    if device.isExposureModeSupported(.locked) { device.exposureMode = .locked }
                    if device.isWhiteBalanceModeSupported(.locked) { device.whiteBalanceMode = .locked }
                } else {
                    if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
                    if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { device.whiteBalanceMode = .continuousAutoWhiteBalance }
                }
            } catch {
                log.debug("Cannot lock camera configuration: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: Delegate

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(pb, CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
    }
}
