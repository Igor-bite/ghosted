import CoreMedia
import CoreMediaIO
import CoreVideo
import Foundation
import os.log
import VanishCore

private let log = Logger(subsystem: "com.vanishcam.Vanish", category: "sink")

/// Feeds rendered frames into the Vanish Camera extension's sink stream through the CMIO HAL.
/// Not thread-safe: use from the pipeline queue only.
final class VirtualCameraSink {
    private var deviceID: CMIOObjectID?
    private var sinkStreamID: CMIOStreamID?
    private var queue: CMSimpleQueue?
    private var formatDescription: CMFormatDescription?

    var isConnected: Bool { queue != nil }

    init() {
        // Allow this process to see virtual/DAL devices without additional prompts.
        var allow: UInt32 = 1
        var addr = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        CMIOObjectSetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil,
                                  UInt32(MemoryLayout<UInt32>.size), &allow)
    }

    deinit { disconnect() }

    /// Finds the device and starts the sink stream. Returns true when connected.
    @discardableResult
    func connect() -> Bool {
        if isConnected { return true }
        guard let device = Self.findDevice() else { return false }
        guard let sink = Self.streams(of: device).first(where: { Self.name(of: $0) == VanishConstants.sinkStreamName })
        else {
            log.error("Sink stream not found")
            return false
        }

        let queuePtr = UnsafeMutablePointer<Unmanaged<CMSimpleQueue>?>.allocate(capacity: 1)
        defer { queuePtr.deallocate() }
        let status = CMIOStreamCopyBufferQueue(sink, { _, _, _ in }, nil, queuePtr)
        guard status == noErr, let q = queuePtr.pointee?.takeRetainedValue() else {
            log.error("CMIOStreamCopyBufferQueue failed: \(status)")
            return false
        }
        let start = CMIODeviceStartStream(device, sink)
        guard start == noErr else {
            log.error("CMIODeviceStartStream failed: \(start)")
            return false
        }
        deviceID = device
        sinkStreamID = sink
        queue = q
        log.info("Connected to Vanish Camera sink")
        return true
    }

    func disconnect() {
        if let deviceID, let sinkStreamID {
            CMIODeviceStopStream(deviceID, sinkStreamID)
        }
        deviceID = nil
        sinkStreamID = nil
        queue = nil
    }

    /// Enqueues a frame; drops it if the extension has not consumed the previous one.
    func send(_ pixelBuffer: CVPixelBuffer, time: CMTime) {
        guard let queue else { return }
        guard CMSimpleQueueGetCount(queue) < CMSimpleQueueGetCapacity(queue) else { return }

        if formatDescription == nil {
            CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                         imageBuffer: pixelBuffer,
                                                         formatDescriptionOut: &formatDescription)
        }
        guard let formatDescription else { return }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: VanishConstants.fps),
                                        presentationTimeStamp: time, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        let err = CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault,
                                                           imageBuffer: pixelBuffer,
                                                           formatDescription: formatDescription,
                                                           sampleTiming: &timing,
                                                           sampleBufferOut: &sample)
        guard err == noErr, let sample else { return }
        let enq = CMSimpleQueueEnqueue(queue, element: Unmanaged.passRetained(sample).toOpaque())
        if enq != noErr {
            Unmanaged.passUnretained(sample).release()
            log.debug("Enqueue failed: \(enq)")
            disconnect()
        }
    }

    /// Who is watching Vanish Camera (from the extension's custom property).
    static func readClients() -> ClientInfo? {
        guard let device = findDevice() else { return nil }
        var addr = CMIOObjectPropertyAddress(
            mSelector: VanishConstants.clientsPropertySelector,
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        guard CMIOObjectHasProperty(device, &addr) else { return nil }
        var value: Unmanaged<CFString>?
        var used: UInt32 = 0
        let size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            CMIOObjectGetPropertyData(device, &addr, 0, nil, size, &used, $0)
        }
        guard status == noErr, let str = value?.takeRetainedValue() else { return nil }
        return ClientInfo(encoded: str as String)
    }

    static var isDevicePresent: Bool { findDevice() != nil }

    // MARK: - HAL helpers

    private static func findDevice() -> CMIOObjectID? {
        var addr = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, &size) == noErr,
              size > 0 else { return nil }
        let count = Int(size) / MemoryLayout<CMIOObjectID>.size
        var devices = [CMIOObjectID](repeating: 0, count: count)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, size, &used, &devices) == noErr
        else { return nil }
        return devices.first { uid(of: $0) == VanishConstants.deviceID.uuidString || name(of: $0) == VanishConstants.deviceName }
    }

    private static func streams(of device: CMIOObjectID) -> [CMIOStreamID] {
        var addr = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyStreams),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(device, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [CMIOStreamID](repeating: 0, count: Int(size) / MemoryLayout<CMIOStreamID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(device, &addr, 0, nil, size, &used, &ids) == noErr else { return [] }
        return ids
    }

    private static func name(of object: CMIOObjectID) -> String? {
        stringProperty(object, selector: CMIOObjectPropertySelector(kCMIOObjectPropertyName))
    }

    private static func uid(of object: CMIOObjectID) -> String? {
        stringProperty(object, selector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceUID))
    }

    private static func stringProperty(_ object: CMIOObjectID, selector: CMIOObjectPropertySelector) -> String? {
        var addr = CMIOObjectPropertyAddress(
            mSelector: selector,
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        guard CMIOObjectHasProperty(object, &addr) else { return nil }
        var value: Unmanaged<CFString>?
        var used: UInt32 = 0
        let size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            CMIOObjectGetPropertyData(object, &addr, 0, nil, size, &used, $0)
        }
        guard status == noErr, let s = value?.takeRetainedValue() else { return nil }
        return s as String
    }
}
