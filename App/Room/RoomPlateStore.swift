import AppKit
import CoreImage
import CoreVideo
import Foundation
import VanishCore

/// Empty-room snapshot: capture (median of frames), validation, persistence.
final class RoomPlateStore {
    struct Plate {
        let image: CIImage
        let cameraID: String?
    }

    enum CaptureResult {
        case ok
        case personDetected(coverage: Double)
        case failed
    }

    static let framesToCapture = 15

    private let dir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Vanish", isDirectory: true)
    }()
    private var imageURL: URL { dir.appendingPathComponent("room.png") }
    private var metaURL: URL { dir.appendingPathComponent("room.json") }

    func load() -> Plate? {
        guard let img = CIImage(contentsOf: imageURL) else { return nil }
        let meta = (try? Data(contentsOf: metaURL)).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) }
        return Plate(image: img, cameraID: meta?["cameraID"])
    }

    func delete() {
        try? FileManager.default.removeItem(at: imageURL)
        try? FileManager.default.removeItem(at: metaURL)
    }

    /// Copies a BGRA frame into packed bytes (no row padding).
    static func packedBytes(_ pb: CVPixelBuffer) -> [UInt8] {
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb)
        let stride = CVPixelBufferGetBytesPerRow(pb)
        var out = [UInt8](repeating: 0, count: w * h * 4)
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return out }
        out.withUnsafeMutableBytes { dst in
            for y in 0..<h {
                memcpy(dst.baseAddress! + y * w * 4, base + y * stride, w * 4)
            }
        }
        return out
    }

    /// Builds the plate from captured frames, checks it for people, saves it.
    func finish(frames: [[UInt8]], width: Int, height: Int, cameraID: String?,
                segmenter: PersonSegmenter) -> (CaptureResult, Plate?) {
        guard !frames.isEmpty else { return (.failed, nil) }
        var median = RoomPlateStats.median(frames)
        // Force opaque alpha.
        for i in Swift.stride(from: 3, to: median.count, by: 4) { median[i] = 255 }

        guard let pb = makeBuffer(bytes: median, width: width, height: height) else { return (.failed, nil) }
        let coverage: Double
        if let raw = segmenter.rawMask(for: pb) {
            coverage = RoomPlateStats.coverage(mask: Self.bytes(ofMask: raw), threshold: 128)
        } else {
            coverage = 0
        }

        let image = CIImage(cvPixelBuffer: pb)
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(image, from: image.extent) else { return (.failed, nil) }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let png = rep.representation(using: .png, properties: [:]) else { return (.failed, nil) }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try png.write(to: imageURL, options: .atomic)
            let meta = ["cameraID": cameraID ?? ""]
            try JSONEncoder().encode(meta).write(to: metaURL, options: .atomic)
        } catch {
            return (.failed, nil)
        }
        let plate = Plate(image: CIImage(cgImage: cg), cameraID: cameraID)
        if RoomPlateStats.containsPerson(coverage: coverage) {
            return (.personDetected(coverage: coverage), plate)
        }
        return (.ok, plate)
    }

    private func makeBuffer(bytes: [UInt8], width: Int, height: Int) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        let attrs: [CFString: Any] = [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary]
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                                  attrs as CFDictionary, &pb) == kCVReturnSuccess, let pb else { return nil }
        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }
        let stride = CVPixelBufferGetBytesPerRow(pb)
        let base = CVPixelBufferGetBaseAddress(pb)!
        bytes.withUnsafeBytes { src in
            for y in 0..<height {
                memcpy(base + y * stride, src.baseAddress! + y * width * 4, width * 4)
            }
        }
        return pb
    }

    private static func bytes(ofMask pb: CVPixelBuffer) -> [UInt8] {
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb)
        let stride = CVPixelBufferGetBytesPerRow(pb)
        var out = [UInt8](repeating: 0, count: w * h)
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return out }
        out.withUnsafeMutableBytes { dst in
            for y in 0..<h { memcpy(dst.baseAddress! + y * w, base + y * stride, w) }
        }
        return out
    }
}
