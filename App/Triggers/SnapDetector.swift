import AVFoundation
import os.log
import SoundAnalysis
import VanishCore

private let log = Logger(subsystem: "com.vanishcam.Vanish", category: "snap")

/// Listens to the microphone with Apple's built-in sound classifier and reports finger snaps.
final class SnapDetector: NSObject, SNResultsObserving {
    var onSnap: (() -> Void)?
    var threshold: Double = 0.8

    private var engine: AVAudioEngine?
    private var analyzer: SNAudioStreamAnalyzer?
    private let analysisQueue = DispatchQueue(label: "vanish.snap.analysis")
    private var gate = GestureGate(holdDuration: 0, cooldown: 2)

    var isRunning: Bool { engine?.isRunning ?? false }

    func start() throws {
        guard engine == nil else { return }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let analyzer = SNAudioStreamAnalyzer(format: format)
        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        request.overlapFactor = 0.75
        try analyzer.add(request, withObserver: self)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [analysisQueue] buffer, when in
            analysisQueue.async { analyzer.analyze(buffer, atAudioFramePosition: when.sampleTime) }
        }
        try engine.start()
        self.engine = engine
        self.analyzer = analyzer
    }

    func stop() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        analysisQueue.async { [analyzer] in analyzer?.removeAllRequests() }
        analyzer = nil
    }

    /// Any other trigger starts the cooldown.
    func noteTrigger() {
        let now = ProcessInfo.processInfo.systemUptime
        analysisQueue.async { self.gate.noteTrigger(now: now) }
    }

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult else { return }
        let confidence = result.classification(forIdentifier: "finger_snapping")?.confidence ?? 0
        let now = ProcessInfo.processInfo.systemUptime
        if gate.update(detected: confidence >= threshold, now: now) {
            log.info("Snap detected (\(confidence, privacy: .public))")
            DispatchQueue.main.async { self.onSnap?() }
        }
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        log.error("Sound analysis failed: \(error.localizedDescription, privacy: .public)")
    }
}
