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
        var dustEnabled = true
        var hybridRoom = true
        var effectDuration: TimeInterval = 1.8
        var vSignEnabled = false
    }

    struct Status: Equatable {
        var running = false
        var hasPlate = false
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
    private var running = false
    private var lastFrameTime: CMTime?
    private var snapshot: (frame: CVPixelBuffer, mask: CVPixelBuffer, bboxX: SIMD2<Float>)?
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
            self.sm.duration = c.dustEnabled ? c.effectDuration : 0.15
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
            } else if plate != nil {
                sm.restore(vanished: true)
            } else {
                DispatchQueue.main.async { self.onNeedsRoomPlate?() }
            }
            publishStatus()
            return
        }
        switch sm.trigger(hasRoomPlate: plate != nil) {
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

        let live = compositor.outputImage(from: frame)
        guard let out = compositor.makeBuffer() else { return }
        var liveBuffer: CVPixelBuffer = out

        switch sm.phase {
        case .present:
            compositor.render(live, into: out)

        case .vanished:
            guard let plate else { compositor.render(live, into: out); break }
            if config.hybridRoom || config.vSignEnabled || roomFrames != nil, let lb = compositor.makeBuffer() {
                compositor.render(live, into: lb)
                liveBuffer = lb
            }
            let mask = config.hybridRoom ? segmenter.mask(for: liveBuffer, size: compositor.size) : nil
            // Privacy first: if segmentation fails, show the static room.
            compositor.render(compositor.roomImage(live: live, plate: plate, mask: mask, hybrid: config.hybridRoom), into: out)
            dumpIfNeeded(live: live, mask: mask, plate: plate, out: out)

        case .vanishing(let p), .appearing(let p):
            let progress: Double
            if case .vanishing = sm.phase { progress = p } else { progress = 1 - p }
            guard let plate, let lb = compositor.makeBuffer() else { compositor.render(live, into: out); break }
            compositor.render(live, into: lb)
            liveBuffer = lb
            if config.dustEnabled {
                renderDust(live: live, liveBuffer: lb, plate: plate, progress: progress, into: out)
            } else {
                let mask = config.hybridRoom ? segmenter.mask(for: lb, size: compositor.size) : nil
                let room = compositor.roomImage(live: live, plate: plate, mask: mask, hybrid: config.hybridRoom)
                compositor.render(compositor.crossfade(from: live, to: room, t: progress), into: out)
            }
        }

        let hostTime = CMClockGetTime(CMClockGetHostTimeClock())
        sink.send(out, time: hostTime)
        onFrame?(out)

        if config.vSignEnabled, vSign.process(liveBuffer, now: hostTime.seconds) {
            DispatchQueue.main.async { self.onGestureTrigger?() }
        }

        if roomFrames != nil {
            if liveBuffer === out && sm.phase != .present, let lb = compositor.makeBuffer() {
                compositor.render(live, into: lb)
                liveBuffer = lb
            }
            collectRoomFrame(liveBuffer)
        }
    }

    private func renderDust(live: CIImage, liveBuffer: CVPixelBuffer, plate: CIImage, progress: Double, into out: CVPixelBuffer) {
        guard let raw = segmenter.rawMask(for: liveBuffer),
              let maskBuffer = compositor.makeMaskBuffer(),
              let roomBuffer = compositor.makeBuffer() else {
            // Segmentation failed: fall back to a crossfade so we never get stuck.
            compositor.render(compositor.crossfade(from: live, to: plate, t: progress), into: out)
            return
        }
        let mask = PersonSegmenter.process(raw, size: compositor.size,
                                           dilate: segmenter.dilateRadius, feather: segmenter.featherRadius)
        compositor.renderMask(mask, into: maskBuffer)
        compositor.render(compositor.roomImage(live: live, plate: plate, mask: mask, hybrid: config.hybridRoom), into: roomBuffer)
        if snapshot == nil {
            snapshot = (liveBuffer, maskBuffer, Compositor.personBoundsX(rawMask: raw))
        }
        guard let snapshot else { return }
        dust.render(.init(live: liveBuffer, room: roomBuffer, mask: maskBuffer,
                          snapshot: snapshot.frame, snapshotMask: snapshot.mask, bboxX: snapshot.bboxX),
                    progress: Float(progress), into: out)
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
                       hasPlate: plate != nil,
                       plateCameraMismatch: plate != nil && plateCameraID != nil && !(plateCameraID ?? "").isEmpty
                           && capture.currentDeviceID != nil && plateCameraID != capture.currentDeviceID,
                       targetHidden: sm.targetHidden,
                       sinkConnected: sink.isConnected)
        guard s != lastStatus else { return }
        lastStatus = s
        DispatchQueue.main.async { self.onStatus?(s) }
    }
}
