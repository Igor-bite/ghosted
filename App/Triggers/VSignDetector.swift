import CoreVideo
import Vision
import VanishCore

/// Detects a held "V" sign with Vision hand pose, ~10 Hz. Use from the pipeline queue.
final class VSignDetector {
    private let request: VNDetectHumanHandPoseRequest = {
        let r = VNDetectHumanHandPoseRequest()
        r.maximumHandCount = 2
        return r
    }()
    private var gate = GestureGate(holdDuration: 0.5, cooldown: 2)
    private var lastRun: TimeInterval = -1
    private var lastDetected = false

    private static let jointMap: [VNHumanHandPoseObservation.JointName: HandJoint] = [
        .wrist: .wrist,
        .indexMCP: .indexMCP, .indexPIP: .indexPIP, .indexTip: .indexTip,
        .middleMCP: .middleMCP, .middlePIP: .middlePIP, .middleTip: .middleTip,
        .ringMCP: .ringMCP, .ringPIP: .ringPIP, .ringTip: .ringTip,
        .littleMCP: .littleMCP, .littlePIP: .littlePIP, .littleTip: .littleTip,
    ]

    /// Returns true when the gesture should trigger the effect.
    func process(_ pixelBuffer: CVPixelBuffer, now: TimeInterval) -> Bool {
        if now - lastRun >= 0.1 {
            lastRun = now
            lastDetected = detect(pixelBuffer)
        }
        return gate.update(detected: lastDetected, now: now)
    }

    func noteTrigger(now: TimeInterval) { gate.noteTrigger(now: now) }

    private func detect(_ pb: CVPixelBuffer) -> Bool {
        let handler = VNImageRequestHandler(cvPixelBuffer: pb, orientation: .up)
        guard (try? handler.perform([request])) != nil, let hands = request.results else { return false }
        for hand in hands {
            guard let pts = try? hand.recognizedPoints(.all) else { continue }
            var pose: [HandJoint: CGPoint] = [:]
            for (name, joint) in Self.jointMap {
                if let p = pts[name], p.confidence > 0.3 { pose[joint] = p.location }
            }
            if VSignClassifier.isVSign(HandPose(points: pose)) { return true }
        }
        return false
    }
}
