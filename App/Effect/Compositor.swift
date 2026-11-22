import CoreImage
import CoreVideo
import Metal
import simd
import VanishCore

/// Core Image side of rendering: crop/scale, room composition, buffer pools.
final class Compositor {
    let size = CGSize(width: Int(VanishConstants.width), height: Int(VanishConstants.height))
    let device: MTLDevice
    let ciContext: CIContext
    private var bgraPool: CVPixelBufferPool?
    private var maskPool: CVPixelBufferPool?

    init?() {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        self.device = device
        ciContext = CIContext(mtlDevice: device, options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            .cacheIntermediates: false,
        ])
        bgraPool = Self.makePool(format: kCVPixelFormatType_32BGRA, size: size, min: 12)
        maskPool = Self.makePool(format: kCVPixelFormatType_OneComponent8, size: size, min: 6)
    }

    private static func makePool(format: OSType, size: CGSize, min: Int) -> CVPixelBufferPool? {
        let attrs: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: format,
            kCVPixelBufferWidthKey: Int(size.width),
            kCVPixelBufferHeightKey: Int(size.height),
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
            kCVPixelBufferMetalCompatibilityKey: true,
        ]
        var pool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(kCFAllocatorDefault,
                                [kCVPixelBufferPoolMinimumBufferCountKey: min] as CFDictionary,
                                attrs as CFDictionary, &pool)
        return pool
    }

    func makeBuffer() -> CVPixelBuffer? {
        guard let bgraPool else { return nil }
        var pb: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, bgraPool, &pb)
        return pb
    }

    func makeMaskBuffer() -> CVPixelBuffer? {
        guard let maskPool else { return nil }
        var pb: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, maskPool, &pb)
        return pb
    }

    /// Camera frame → 1280×720 CIImage (center crop, aspect fill). Origin at (0,0).
    func outputImage(from cameraFrame: CVPixelBuffer) -> CIImage {
        let img = CIImage(cvPixelBuffer: cameraFrame)
        let src = img.extent.size
        // CIImage origin is bottom-left; aspectFillRect is symmetric so the centered crop is identical.
        let crop = aspectFillRect(source: src, target: size)
        let scale = size.width / crop.width
        return img.cropped(to: crop)
            .transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .cropped(to: CGRect(origin: .zero, size: size))
    }

    // MARK: Room composition

    /// Per-channel exposure/white-balance gain mapping the plate onto the current live frame.
    private var gain = SIMD3<Double>(repeating: 1)
    private var roomFrameCounter = 0
    /// Mean colour difference (0...1) below which a pixel counts as "unchanged" vs the empty room.
    static let changeThreshold = 0.06
    /// Difference range over which a pixel ramps from unchanged to fully changed.
    static let changeRamp = 0.06
    /// Extra band (px at 1280×720) hidden around the person in hybrid mode. Covers the halo that
    /// virtual backgrounds and imperfect segmentation leave at the silhouette edge.
    static let haloRadius = 22.0

    func resetGain() {
        gain = SIMD3(repeating: 1)
        roomFrameCounter = 0
    }

    /// Room view while the person is hidden.
    ///
    /// Full replacement (`hybrid == false`): the whole frame is the room snapshot, so nothing of the
    /// person can leak through. Hybrid: everything that differs from the empty-room plate (the person, but also their cast
    /// shadows and light they block) is replaced by the plate; unchanged areas stay live.
    /// The plate is gain-corrected to the live exposure so no seam shows at the boundary.
    func roomImage(live: CIImage, plate: CIImage, mask: CIImage?, hybrid: Bool) -> CIImage {
        guard hybrid, let mask else { return correctedPlate(plate) }
        let rect = CGRect(origin: .zero, size: size)
        let halo = mask.clampedToExtent()
            .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: Self.haloRadius])
            .applyingGaussianBlur(sigma: Self.haloRadius / 3)
            .cropped(to: rect)
        let hidden = changeMask(live: live, plate: correctedPlate(plate))
            .applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: halo])
            .cropped(to: rect)
        if roomFrameCounter % 10 == 0 { updateGain(live: live, plate: plate, exclude: hidden) }
        roomFrameCounter += 1
        return correctedPlate(plate).applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: live,
            kCIInputMaskImageKey: hidden,
        ]).cropped(to: rect)
    }

    /// Person (white in `mask`) from `person` over `background`.
    func composite(person: CIImage, over background: CIImage, mask: CIImage) -> CIImage {
        person.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: background,
            kCIInputMaskImageKey: mask,
        ]).cropped(to: CGRect(origin: .zero, size: size))
    }

    /// Uploads a CGImage once into an IOSurface-backed buffer so per-frame use costs no CPU→GPU copy.
    func residentImage(_ image: CGImage) -> CIImage? {
        var pb: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
            kCVPixelBufferMetalCompatibilityKey: true,
        ]
        guard CVPixelBufferCreate(kCFAllocatorDefault, Int(size.width), Int(size.height), kCVPixelFormatType_32BGRA,
                                  attrs as CFDictionary, &pb) == kCVReturnSuccess, let pb else { return nil }
        let src = CIImage(cgImage: image)
        let fitted = src.transformed(by: CGAffineTransform(scaleX: size.width / src.extent.width,
                                                           y: size.height / src.extent.height))
        render(fitted, into: pb)
        return CIImage(cvPixelBuffer: pb)
    }

    func correctedPlate(_ plate: CIImage) -> CIImage {
        plate.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: gain.x, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: gain.y, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: gain.z, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ]).cropped(to: CGRect(origin: .zero, size: size))
    }

    /// White where the live frame differs from the (gain-corrected) plate.
    func changeMask(live: CIImage, plate: CIImage) -> CIImage {
        let rect = CGRect(origin: .zero, size: size)
        let k = 1 / Self.changeRamp
        let bias = -Self.changeThreshold * k
        let w = CIVector(x: k / 3, y: k / 3, z: k / 3, w: 0)
        let a = live.clampedToExtent().applyingGaussianBlur(sigma: 1.5).cropped(to: rect)
        let b = plate.clampedToExtent().applyingGaussianBlur(sigma: 1.5).cropped(to: rect)
        return a.applyingFilter("CIDifferenceBlendMode", parameters: [kCIInputBackgroundImageKey: b])
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": w, "inputGVector": w, "inputBVector": w,
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: bias, y: bias, z: bias, w: 1),
            ])
            .applyingFilter("CIColorClamp")
            .clampedToExtent()
            .applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: 2])   // drop noise specks
            .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: 8])   // cover soft shadow edges
            .applyingGaussianBlur(sigma: 5)
            .cropped(to: rect)
    }

    /// Measures live/plate brightness ratio over pixels that are not hidden and eases the gain toward it.
    private func updateGain(live: CIImage, plate: CIImage, exclude: CIImage) {
        let keep = exclude.applyingFilter("CIColorInvert")
        let l = average(live.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: keep]))
        let p = average(plate.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: keep]))
        guard p.min() > 0.02 else { return }
        let measured = simd_clamp(l / p, SIMD3(repeating: 0.6), SIMD3(repeating: 1.6))
        gain += (measured - gain) * 0.5
    }

    private func average(_ image: CIImage) -> SIMD3<Double> {
        let rect = CGRect(origin: .zero, size: size)
        let avg = image.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: rect)])
        var px = [Float](repeating: 0, count: 4)
        ciContext.render(avg, toBitmap: &px, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                         format: .RGBAf, colorSpace: nil)
        return SIMD3(Double(px[0]), Double(px[1]), Double(px[2]))
    }

    func crossfade(from a: CIImage, to b: CIImage, t: Double) -> CIImage {
        a.applyingFilter("CIDissolveTransition", parameters: [
            kCIInputTargetImageKey: b,
            kCIInputTimeKey: max(0, min(1, t)),
        ]).cropped(to: CGRect(origin: .zero, size: size))
    }

    func render(_ image: CIImage, into pb: CVPixelBuffer) {
        ciContext.render(image, to: pb, bounds: CGRect(origin: .zero, size: size),
                         colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
    }

    func renderMask(_ image: CIImage, into pb: CVPixelBuffer) {
        ciContext.render(image, to: pb, bounds: CGRect(origin: .zero, size: size), colorSpace: nil)
    }

    /// Horizontal extent of the person in uv (0...1, x left→right) from a Vision raw mask.
    static func personBoundsX(rawMask: CVPixelBuffer) -> SIMD2<Float> {
        CVPixelBufferLockBaseAddress(rawMask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(rawMask, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(rawMask) else { return SIMD2(0, 1) }
        let w = CVPixelBufferGetWidth(rawMask), h = CVPixelBufferGetHeight(rawMask)
        let stride = CVPixelBufferGetBytesPerRow(rawMask)
        var minX = w, maxX = -1
        let p = base.assumingMemoryBound(to: UInt8.self)
        for y in Swift.stride(from: 0, to: h, by: 2) {
            let row = p + y * stride
            for x in Swift.stride(from: 0, to: w, by: 2) where row[x] > 127 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
            }
        }
        guard maxX >= minX else { return SIMD2(0, 1) }
        return SIMD2(Float(minX) / Float(w), Float(maxX + 1) / Float(w))
    }
}
