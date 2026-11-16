import CoreImage
import Vision

/// Person mask via Vision, post-processed (dilate + feather) to cover hair/hand edges.
/// Use from one queue only.
final class PersonSegmenter {
    private let request: VNGeneratePersonSegmentationRequest = {
        let r = VNGeneratePersonSegmentationRequest()
        r.qualityLevel = .balanced
        r.outputPixelFormat = kCVPixelFormatType_OneComponent8
        return r
    }()
    private let sequence = VNSequenceRequestHandler()

    var dilateRadius: Double = 6
    var featherRadius: Double = 3

    /// Raw mask buffer (Vision resolution), or nil.
    func rawMask(for pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        do {
            try sequence.perform([request], on: pixelBuffer)
            return request.results?.first?.pixelBuffer
        } catch {
            return nil
        }
    }

    /// Mask as a CIImage scaled to `size`, dilated and feathered. White = person.
    func mask(for pixelBuffer: CVPixelBuffer, size: CGSize) -> CIImage? {
        guard let raw = rawMask(for: pixelBuffer) else { return nil }
        return Self.process(raw, size: size, dilate: dilateRadius, feather: featherRadius)
    }

    static func process(_ raw: CVPixelBuffer, size: CGSize, dilate: Double, feather: Double) -> CIImage {
        var img = CIImage(cvPixelBuffer: raw)
        let sx = size.width / img.extent.width
        let sy = size.height / img.extent.height
        img = img.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
        let rect = CGRect(origin: .zero, size: size)
        if dilate > 0 {
            img = img.clampedToExtent().applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: dilate])
        }
        if feather > 0 {
            img = img.clampedToExtent().applyingGaussianBlur(sigma: feather)
        }
        return img.cropped(to: rect)
    }
}
