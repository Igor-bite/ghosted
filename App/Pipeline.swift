import CoreImage
import CoreMedia
import CoreVideo
import Foundation
import os.log
import VanishCore

private let log = Logger(subsystem: "com.vanishcam.Vanish", category: "pipeline")

/// Owns capture → effect → virtual camera. All mutable state lives on `queue` (the capture frame queue).
final class Pipeline {
    struct Config: Equatable {
        var effect: EffectStyle = .dust
        var hybridRoom = true
        var effectDuration: TimeInterval = 1.8
        var vSignEnabled = false
    }

    struct Status: Equatable {
        var running = false
        var hasPlate = false
        var usingVirtualBackground = false
        var plateCameraMismatch = false
        var targetHidden = false
        var sinkConnected = false
    }

    enum RoomCaptureOutcome {
        case ok
        case personDetected
        case failed
    }

    /// Main-queue callbacks.
    var onStatus: ((Status) -> Void)?
    var onNeedsRoomPlate: (() -> Void)?
    var onGestureTrigger: (() -> Void)?
    /// Called on the pipeline queue with every rendered frame (for preview).
    var onFrame: ((CVPixelBuffer) -> Void)?

    let capture = CameraCapture()
    private var queue: DispatchQueue { capture.frameQueue }
    private let compositor: Compositor
    private let dust: DustRenderer
    private let segmenter = PersonSegmenter()
    private let sink = VirtualCameraSink()
    private let vSign = VSignDetector()
    private let store = RoomPlateStore()

    private var config = Config()
    private var sm = EffectStateMachine(duration: 1.8)
    private var plate: CIImage?
    private var plateCameraID: String?
    /// Chosen virtual background (output size, GPU-resident), replacing the room snapshot.
    private var virtualBackground: CIImage?
    private var lastPersonMask: CIImage?
    private var running = false
    private var lastFrameTime: CMTime?
    private var snapshot: (frame: CVPixelBuffer, mask: CVPixelBuffer, bounds: Compositor.PersonBounds)?
    private var roomFrames: [[UInt8]]?
    private var roomCompletion: ((RoomCaptureOutcome) -> Void)?
    private var lastStatus = Status()
    private var reconnectTimer: DispatchSourceTimer?
    private var debugDump = false
    private var debugDumpCount = 0
    private var lastDebugDump: TimeInterval = 0

    init?(restoreHidden: Bool) {
        guard let compositor = Compositor(), let dust = DustRenderer(device: compositor.device) else { return nil }
        self.compositor = compositor
        self.dust = dust
        if let p = store.load() {
            plate = p.image
            plateCameraID = p.cameraID
        }
        // A virtual background arrives later via setVirtualBackground; restore against the room for now.
        sm.restore(vanished: restoreHidden && plate != nil)
        capture.onFrame = { [weak self] pb, time in self?.process(pb, time: time) }

        let t = DispatchSource.makeTimerSource(queue: capture.frameQueue)
        t.schedule(deadline: .now() + 0.5, repeating: 1.0)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            if !self.sink.isConnected { self.sink.connect() }
            self.debugDump = UserDefaults.standard.bool(forKey: "debugDump")
            self.publishStatus()
        }
        t.resume()
        reconnectTimer = t
    }

    // MARK: Commands (thread-safe)

    func setConfig(_ c: Config) {
        queue.async {
            self.config = c
            self.sm.duration = c.effectDuration
        }
    }

    func selectCamera(_ id: String?) { capture.select(uniqueID: id) }

    func setRunning(_ run: Bool) {
        queue.async {
            guard run != self.running else { return }
            self.running = run
            self.lastFrameTime = nil
            if run {
                self.sink.connect()
                self.capture.start()
            } else {
                self.capture.stop()
                // Nobody sees the animation: settle into the target state.
                self.sm.restore(vanished: self.sm.targetHidden)
                self.snapshot = nil
            }
            self.publishStatus()
        }
    }

    func trigger() {
        queue.async { self.triggerOnQueue() }
    }

    func captureRoom(completion: @escaping (RoomCaptureOutcome) -> Void) {
        queue.async {
            self.roomFrames = []
            self.roomCompletion = completion
        }
    }

    /// Sets (or clears with nil) the virtual background. The image is aspect-filled to the output size.
    func setVirtualBackground(_ image: CGImage?) {
        let ci = image.flatMap { compositor.residentImage($0) }
        queue.async {
            self.virtualBackground = ci
            self.lastPersonMask = nil
            if ci == nil && self.plate == nil && self.sm.targetHidden { self.sm.restore(vanished: false) }
            self.publishStatus()
        }
    }

    func deleteRoom() {
        queue.async {
            self.store.delete()
            self.plate = nil
            self.plateCameraID = nil
            self.sm.restore(vanished: false)
            self.publishStatus()
        }
    }

    // MARK: Queue-confined

    private func triggerOnQueue() {
        let now = CMClockGetTime(CMClockGetHostTimeClock()).seconds
        vSign.noteTrigger(now: now)
        let wasPhase = sm.phase
        if !running {
            if sm.targetHidden {
                sm.restore(vanished: false)
            } else if effectivePlate != nil {
                sm.restore(vanished: true)
            } else {
                DispatchQueue.main.async { self.onNeedsRoomPlate?() }
            }
            publishStatus()
            return
        }
        switch sm.trigger(hasRoomPlate: effectivePlate != nil) {
        case .needsRoomPlate:
            DispatchQueue.main.async { self.onNeedsRoomPlate?() }
        case .started:
            snapshot = nil
            if wasPhase == .present { capture.setAutoAdjustmentsLocked(true) }
        case .reversed:
            break
        }
        publishStatus()
    }

    private func process(_ frame: CVPixelBuffer, time: CMTime) {
        guard running else { return }
        let dt = lastFrameTime.map { min(max((time - $0).seconds, 0), 0.1) } ?? 0
        lastFrameTime = time
        let before = sm.phase
        sm.tick(dt: dt)
        if sm.phase != before {
            if sm.phase == .present {
                capture.setAutoAdjustmentsLocked(false)
                snapshot = nil
            } else if sm.phase == .vanished {
                snapshot = nil
            }
            if !sm.isAnimating { publishStatus() }
        }

        let camera = compositor.outputImage(from: frame)
        guard let out = compositor.makeBuffer() else { return }

        // Camera frame at output size for Vision, the V gesture and room capture. Rendered on demand.
        var cameraBuffer: CVPixelBuffer?
        func cameraPB() -> CVPixelBuffer? {
            if cameraBuffer == nil, let b = compositor.makeBuffer() {
                compositor.render(camera, into: b)
                cameraBuffer = b
            }
            return cameraBuffer
        }

        // Virtual background: while visible, the person is composited over the chosen image.
        var live = camera
        var rawMask: CVPixelBuffer?
        if let bg = virtualBackground, sm.phase != .vanished, let cb = cameraPB() {
            rawMask = segmenter.rawMask(for: cb)
            if let rawMask {
                lastPersonMask = PersonSegmenter.process(rawMask, size: compositor.size, dilate: 0, feather: 1.5)
            }
            // Brief segmentation failure: reuse the last mask instead of flashing the real room.
            live = lastPersonMask.map { compositor.composite(person: camera, over: bg, mask: $0) } ?? bg
        }

        switch sm.phase {
        case .present:
            compositor.render(live, into: out)

        case .vanished:
            if let bg = virtualBackground {
                compositor.render(bg, into: out)
            } else if let plate {
                let mask = config.hybridRoom ? cameraPB().flatMap { segmenter.mask(for: $0, size: compositor.size) } : nil
                // Privacy first: if segmentation fails, show the static room.
                compositor.render(compositor.roomImage(live: camera, plate: plate, mask: mask, hybrid: config.hybridRoom), into: out)
                dumpIfNeeded(live: camera, mask: mask, plate: plate, out: out)
            } else {
                compositor.render(camera, into: out)
            }

        case .vanishing(let p), .appearing(let p):
            let progress: Double
            if case .vanishing = sm.phase { progress = p } else { progress = 1 - p }
            guard effectivePlate != nil, let lb = compositor.makeBuffer() else { compositor.render(live, into: out); break }
            compositor.render(live, into: lb)
            if let style = config.effect.shaderStyle {
                renderEffect(style, live: live, liveBuffer: lb, camera: camera, rawMask: rawMask, progress: progress, into: out)
            } else {
                let mask = useHybrid ? segmenter.mask(for: lb, size: compositor.size) : nil
                compositor.render(compositor.crossfade(from: live, to: room(camera: camera, mask: mask), t: progress), into: out)
            }
        }

        let hostTime = CMClockGetTime(CMClockGetHostTimeClock())
        sink.send(out, time: hostTime)
        onFrame?(out)

        // Plain camera output already is the camera frame: reuse it instead of rendering again.
        if cameraBuffer == nil, sm.phase == .present, virtualBackground == nil { cameraBuffer = out }
        if config.vSignEnabled, let cb = cameraPB(), vSign.process(cb, now: hostTime.seconds) {
            DispatchQueue.main.async { self.onGestureTrigger?() }
        }

        if roomFrames != nil, let cb = cameraPB() {
            collectRoomFrame(cb)
        }
    }

    /// Plate in effect: the virtual background if one is chosen, else the empty-room snapshot.
    private var effectivePlate: CIImage? { virtualBackground ?? plate }

    /// Live-room blending only applies to the camera snapshot.
    private var useHybrid: Bool { config.hybridRoom && virtualBackground == nil }

    /// What remains once the person is gone.
    private func room(camera: CIImage, mask: CIImage?) -> CIImage {
        if let bg = virtualBackground { return bg }
        guard let plate else { return camera }
        return compositor.roomImage(live: camera, plate: plate, mask: mask, hybrid: config.hybridRoom)
    }

    private func renderEffect(_ style: DustRenderer.Style, live: CIImage, liveBuffer: CVPixelBuffer, camera: CIImage, rawMask: CVPixelBuffer?,
                            progress: Double, into out: CVPixelBuffer) {
        guard let raw = rawMask ?? segmenter.rawMask(for: liveBuffer),
              let maskBuffer = compositor.makeMaskBuffer(),
              let roomBuffer = compositor.makeBuffer() else {
            // Segmentation failed: fall back to a crossfade so we never get stuck.
            compositor.render(compositor.crossfade(from: live, to: room(camera: camera, mask: nil), t: progress), into: out)
            return
        }
        let mask = PersonSegmenter.process(raw, size: compositor.size,
                                           dilate: segmenter.dilateRadius, feather: segmenter.featherRadius)
        compositor.renderMask(mask, into: maskBuffer)
        compositor.render(room(camera: camera, mask: useHybrid ? mask : nil), into: roomBuffer)
        if snapshot == nil {
            snapshot = (liveBuffer, maskBuffer, Compositor.personBounds(rawMask: raw))
        }
        guard let snapshot else { return }
        dust.render(.init(live: liveBuffer, room: roomBuffer, mask: maskBuffer,
                          snapshot: snapshot.frame, snapshotMask: snapshot.mask, bounds: snapshot.bounds),
                    style: style, progress: Float(progress), into: out)
    }

    private func collectRoomFrame(_ pb: CVPixelBuffer) {
        roomFrames?.append(RoomPlateStore.packedBytes(pb))
        guard let frames = roomFrames, frames.count >= RoomPlateStore.framesToCapture else { return }
        roomFrames = nil
        let completion = roomCompletion
        roomCompletion = nil
        let cameraID = capture.currentDeviceID
        let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb)
        DispatchQueue.global(qos: .userInitiated).async {
            let (result, newPlate) = self.store.finish(frames: frames, width: w, height: h,
                                                       cameraID: cameraID, segmenter: PersonSegmenter())
            self.queue.async {
                if let newPlate {
                    self.plate = newPlate.image
                    self.plateCameraID = newPlate.cameraID
                    self.compositor.resetGain()
                }
                self.publishStatus()
                let outcome: RoomCaptureOutcome
                switch result {
                case .ok: outcome = .ok
                case .personDetected: outcome = .personDetected
                case .failed: outcome = .failed
                }
                DispatchQueue.main.async { completion?(outcome) }
            }
        }
    }

    /// Debug aid: `defaults write com.vanishcam.Vanish debugDump -bool true` saves 3 sets of
    /// live / mask / plate / output PNGs to ~/Library/Application Support/Vanish/debug.
    private func dumpIfNeeded(live: CIImage, mask: CIImage?, plate: CIImage, out: CVPixelBuffer) {
        guard debugDump, debugDumpCount < 3 else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastDebugDump > 2 else { return }
        lastDebugDump = now
        debugDumpCount += 1
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Vanish/debug", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ctx = compositor.ciContext
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let n = debugDumpCount
        func save(_ img: CIImage, _ name: String) {
            try? ctx.writePNGRepresentation(of: img.cropped(to: CGRect(origin: .zero, size: compositor.size)),
                                            to: dir.appendingPathComponent("\(n)-\(name).png"), format: .RGBA8, colorSpace: cs)
        }
        save(live, "live")
        save(plate, "plate")
        if let mask { save(mask, "mask") }
        save(CIImage(cvPixelBuffer: out), "out")
        log.info("Debug dump \(n) written")
    }

    private func publishStatus() {
        let s = Status(running: running,
                       hasPlate: effectivePlate != nil,
                       usingVirtualBackground: virtualBackground != nil,
                       plateCameraMismatch: virtualBackground == nil && plate != nil && plateCameraID != nil && !(plateCameraID ?? "").isEmpty
                           && capture.currentDeviceID != nil && plateCameraID != capture.currentDeviceID,
                       targetHidden: sm.targetHidden,
                       sinkConnected: sink.isConnected)
        guard s != lastStatus else { return }
        lastStatus = s
        DispatchQueue.main.async { self.onStatus?(s) }
    }
}
