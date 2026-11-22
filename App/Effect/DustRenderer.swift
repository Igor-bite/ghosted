import CoreVideo
import Metal
import simd

/// Mirrors `DustParams` in Dust.metal (keep layout in sync).
struct DustParams {
    var progress: Float
    var life: Float
    var size: SIMD2<Float>
    var wind: SIMD2<Float>
    var bboxX: SIMD2<Float>
    var bboxY: SIMD2<Float>
    var gridStep: UInt32
    var gridWidth: UInt32
    var pointSize: Float
    var style: UInt32
}

/// GPU part of the shader effects: dissolve pass (+ particle pass for dust) into an output pixel buffer.
final class DustRenderer {
    /// Matches `style` in Dust.metal.
    enum Style: UInt32 {
        case dust = 0
        case glitch = 1
        case beam = 2
    }

    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let dissolvePipeline: MTLRenderPipelineState
    private let particlePipeline: MTLRenderPipelineState
    private var textureCache: CVMetalTextureCache?

    static let gridStep: UInt32 = 2
    static let life: Float = 0.38

    init?(device: MTLDevice, library: MTLLibrary? = nil) {
        guard let queue = device.makeCommandQueue(),
              let library = library ?? device.makeDefaultLibrary() else { return nil }
        self.device = device
        self.queue = queue

        let d = MTLRenderPipelineDescriptor()
        d.vertexFunction = library.makeFunction(name: "fullscreenVertex")
        d.fragmentFunction = library.makeFunction(name: "dissolveFragment")
        d.colorAttachments[0].pixelFormat = .bgra8Unorm

        let p = MTLRenderPipelineDescriptor()
        p.vertexFunction = library.makeFunction(name: "particleVertex")
        p.fragmentFunction = library.makeFunction(name: "particleFragment")
        p.colorAttachments[0].pixelFormat = .bgra8Unorm
        p.colorAttachments[0].isBlendingEnabled = true
        p.colorAttachments[0].sourceRGBBlendFactor = .one
        p.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        p.colorAttachments[0].sourceAlphaBlendFactor = .one
        p.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        do {
            dissolvePipeline = try device.makeRenderPipelineState(descriptor: d)
            particlePipeline = try device.makeRenderPipelineState(descriptor: p)
        } catch {
            return nil
        }
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
    }

    struct Inputs {
        var live: CVPixelBuffer
        var room: CVPixelBuffer
        var mask: CVPixelBuffer          // OneComponent8, live mask
        var snapshot: CVPixelBuffer      // frame at animation start
        var snapshotMask: CVPixelBuffer  // OneComponent8
        var bounds: Compositor.PersonBounds  // person bbox (uv) at animation start
    }

    /// `progress`: 0 = person intact, 1 = fully dust.
    func render(_ inputs: Inputs, style: Style, progress: Float, into output: CVPixelBuffer) {
        guard let live = texture(inputs.live, .bgra8Unorm),
              let room = texture(inputs.room, .bgra8Unorm),
              let mask = texture(inputs.mask, .r8Unorm),
              let snap = texture(inputs.snapshot, .bgra8Unorm),
              let snapMask = texture(inputs.snapshotMask, .r8Unorm),
              let out = texture(output, .bgra8Unorm),
              let cmd = queue.makeCommandBuffer() else { return }

        let w = CVPixelBufferGetWidth(output), h = CVPixelBufferGetHeight(output)
        let gridW = UInt32(w) / Self.gridStep
        let gridH = UInt32(h) / Self.gridStep
        var params = DustParams(progress: progress, life: Self.life,
                                size: SIMD2(Float(w), Float(h)),
                                wind: SIMD2(1.0, -0.35),
                                bboxX: inputs.bounds.x,
                                bboxY: inputs.bounds.y,
                                gridStep: Self.gridStep, gridWidth: gridW,
                                pointSize: Float(Self.gridStep) * 1.6,
                                style: style.rawValue)

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = out
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { return }

        enc.setRenderPipelineState(dissolvePipeline)
        enc.setFragmentTexture(live, index: 0)
        enc.setFragmentTexture(room, index: 1)
        enc.setFragmentTexture(mask, index: 2)
        enc.setFragmentBytes(&params, length: MemoryLayout<DustParams>.stride, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

        if style != .glitch {
            enc.setRenderPipelineState(particlePipeline)
            enc.setVertexTexture(snap, index: 0)
            enc.setVertexTexture(snapMask, index: 1)
            enc.setVertexBytes(&params, length: MemoryLayout<DustParams>.stride, index: 0)
            enc.drawPrimitives(type: .point, vertexStart: 0, vertexCount: Int(gridW * gridH))
        }
        enc.endEncoding()

        cmd.commit()
        cmd.waitUntilCompleted()
    }

    private func texture(_ pb: CVPixelBuffer, _ format: MTLPixelFormat) -> MTLTexture? {
        guard let cache = textureCache else { return nil }
        var tex: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, cache, pb, nil, format,
                                                  CVPixelBufferGetWidth(pb), CVPixelBufferGetHeight(pb), 0, &tex)
        return tex.flatMap(CVMetalTextureGetTexture)
    }
}

extension EffectStyle {
    /// Shader style, or nil for the Core Image crossfade.
    var shaderStyle: DustRenderer.Style? {
        switch self {
        case .dust: return .dust
        case .glitch: return .glitch
        case .beam: return .beam
        case .fade: return nil
        }
    }
}
