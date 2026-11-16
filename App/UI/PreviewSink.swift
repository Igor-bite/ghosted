import AppKit
import CoreVideo
import QuartzCore
import SwiftUI

/// Displays pipeline frames in a CALayer (IOSurface contents, no copies).
final class PreviewSink: @unchecked Sendable {
    let layer: CALayer = {
        let l = CALayer()
        l.contentsGravity = .resizeAspect
        l.backgroundColor = NSColor.black.cgColor
        return l
    }()
    private let lock = NSLock()
    private var pending: CVPixelBuffer?
    private var scheduled = false

    func push(_ pb: CVPixelBuffer) {
        lock.lock()
        pending = pb
        let needSchedule = !scheduled
        scheduled = true
        lock.unlock()
        guard needSchedule else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let pb = self.pending
            self.pending = nil
            self.scheduled = false
            self.lock.unlock()
            guard let pb, let surface = CVPixelBufferGetIOSurface(pb)?.takeUnretainedValue() else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.layer.contents = surface
            CATransaction.commit()
        }
    }
}

struct PreviewLayerView: NSViewRepresentable {
    let sink: PreviewSink

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer = CALayer()
        v.layer?.backgroundColor = NSColor.black.cgColor
        sink.layer.frame = v.bounds
        sink.layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        v.layer?.addSublayer(sink.layer)
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
