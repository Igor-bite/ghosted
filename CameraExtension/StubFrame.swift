import AppKit
import CoreText
import CoreVideo

/// Static frame shown when Ghosted.app is not feeding frames. Bilingual because
/// the extension runs as a system user and cannot know the user's language.
enum StubFrame {
    static func make(width: Int, height: Int) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        let attrs: [CFString: Any] = [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary]
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                                  attrs as CFDictionary, &pb) == kCVReturnSuccess, let pb else { return nil }
        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }
        guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb),
                                  width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }

        // Background gradient.
        let colors = [CGColor(red: 0.04, green: 0.03, blue: 0.09, alpha: 1),
                      CGColor(red: 0.11, green: 0.07, blue: 0.25, alpha: 1),
                      CGColor(red: 0.23, green: 0.12, blue: 0.53, alpha: 1)] as CFArray
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.6, 1]) {
            ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: height), options: [])
        }

        // Dust dots motif.
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<220 {
            let x = CGFloat.random(in: CGFloat(width) * 0.55...CGFloat(width) * 0.95, using: &rng)
            let y = CGFloat.random(in: CGFloat(height) * 0.15...CGFloat(height) * 0.85, using: &rng)
            let r = CGFloat.random(in: 1...3.5, using: &rng)
            let t = (x - CGFloat(width) * 0.55) / (CGFloat(width) * 0.4)
            ctx.setFillColor(CGColor(red: 0.86 - 0.73 * t, green: 0.82 + 0.0 * t, blue: 1.0 - 0.07 * t,
                                     alpha: CGFloat.random(in: 0.1...0.5, using: &rng)))
            ctx.fillEllipse(in: CGRect(x: x, y: y, width: r, height: r))
        }

        draw("Ghosted", size: 72, weight: .semibold, alpha: 1, y: CGFloat(height) * 0.56, ctx: ctx, width: width)
        draw("Откройте приложение Ghosted", size: 34, weight: .regular, alpha: 0.85, y: CGFloat(height) * 0.43, ctx: ctx, width: width)
        draw("Open the Ghosted app", size: 34, weight: .regular, alpha: 0.6, y: CGFloat(height) * 0.36, ctx: ctx, width: width)
        return pb
    }

    private static func draw(_ text: String, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat,
                             y: CGFloat, ctx: CGContext, width: Int) {
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        let attr = NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: NSColor(white: 1, alpha: alpha),
        ])
        let line = CTLineCreateWithAttributedString(attr)
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        ctx.textPosition = CGPoint(x: (CGFloat(width) - bounds.width) / 2 - bounds.minX, y: y)
        CTLineDraw(line, ctx)
    }
}
