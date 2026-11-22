#if DEBUG
import AppKit
import CoreImage
import SwiftUI

/// Debug aid: `open -n Ghosted.app --args -snapshotDir /path` renders every main-window tab, the menu
/// and a few frames of each shader effect (on a synthetic silhouette) into PNGs, then quits.
@MainActor
enum Snapshotter {
    static func runIfRequested() {
        guard let dir = UserDefaults.standard.string(forKey: "snapshotDir") else { return }
        let url = URL(fileURLWithPath: dir, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            let model = AppModel.shared
            for tab in MainTab.allCases {
                model.mainTab = tab
                try? await Task.sleep(nanoseconds: 600_000_000)
                render(MainWindow(), size: CGSize(width: 760, height: 580), to: url.appendingPathComponent("tab-\(tab.rawValue).png"))
            }
            render(MenuView(), size: CGSize(width: 320, height: 520), to: url.appendingPathComponent("menu.png"))
            renderEffects(to: url)
            NSApp.terminate(nil)
        }
    }

    private static func render<V: View>(_ view: V, size: CGSize, to file: URL) {
        let model = AppModel.shared
        let root = view
            .environmentObject(model)
            .environmentObject(model.settings)
            .environmentObject(model.installer)
            .frame(width: size.width, height: size.height)
            .background(Color(nsColor: .windowBackgroundColor))
        let host = NSHostingView(rootView: root)
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.layoutIfNeeded()
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: file)
    }

    /// Synthetic scene: striped "room", a warm silhouette (head + shoulders) on a lighter live frame.
    private static func renderEffects(to dir: URL) {
        guard let compositor = Compositor(), let renderer = DustRenderer(device: compositor.device),
              let live = compositor.makeBuffer(), let room = compositor.makeBuffer(),
              let mask = compositor.makeMaskBuffer() else { return }
        let size = compositor.size
        let rect = CGRect(origin: .zero, size: size)
        let roomImg = CIFilter(name: "CIStripesGenerator", parameters: [
            "inputColor0": CIColor(red: 0.18, green: 0.2, blue: 0.26), "inputColor1": CIColor(red: 0.24, green: 0.27, blue: 0.33),
            "inputWidth": 40,
        ])!.outputImage!.cropped(to: rect)
        // CI origin is bottom-left: head near the top, body down to the bottom edge.
        let head = CIFilter(name: "CIRadialGradient", parameters: [
            "inputCenter": CIVector(x: 640, y: 470), "inputRadius0": 110, "inputRadius1": 112,
            "inputColor0": CIColor.white, "inputColor1": CIColor.black,
        ])!.outputImage!.cropped(to: rect)
        let body = CIFilter(name: "CIRadialGradient", parameters: [
            "inputCenter": CIVector(x: 640, y: -60), "inputRadius0": 290, "inputRadius1": 292,
            "inputColor0": CIColor.white, "inputColor1": CIColor.black,
        ])!.outputImage!.cropped(to: rect)
        let maskImg = head.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: body])
        let person = CIFilter(name: "CILinearGradient", parameters: [
            "inputPoint0": CIVector(x: 0, y: 0), "inputPoint1": CIVector(x: 0, y: 720),
            "inputColor0": CIColor(red: 0.85, green: 0.45, blue: 0.3), "inputColor1": CIColor(red: 0.95, green: 0.75, blue: 0.55),
        ])!.outputImage!.cropped(to: rect)
        let liveImg = compositor.composite(person: person, over: roomImg.applyingFilter("CIExposureAdjust", parameters: ["inputEV": 0.3]), mask: maskImg)
        compositor.render(roomImg, into: room)
        compositor.render(liveImg, into: live)
        compositor.renderMask(maskImg, into: mask)
        let bounds = Compositor.PersonBounds(x: SIMD2(0.27, 0.73), y: SIMD2(0.18, 1.0))
        for style in [DustRenderer.Style.dust, .glitch, .beam] {
            for p in [0.15, 0.4, 0.65, 0.9] {
                guard let out = compositor.makeBuffer() else { continue }
                renderer.render(.init(live: live, room: room, mask: mask, snapshot: live, snapshotMask: mask, bounds: bounds),
                                style: style, progress: Float(p), into: out)
                let img = CIImage(cvPixelBuffer: out)
                try? compositor.ciContext.writePNGRepresentation(
                    of: img, to: dir.appendingPathComponent("fx-\(style)-\(Int(p * 100)).png"),
                    format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
            }
        }
    }
}
#endif
