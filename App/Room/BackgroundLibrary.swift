import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Virtual backgrounds: built-in presets drawn procedurally plus images the user adds.
/// A selected background replaces the empty-room snapshot: the person is composited over it while
/// present and dissolves into it when vanishing.
@MainActor
final class BackgroundLibrary: ObservableObject {
    struct Item: Identifiable, Hashable {
        let id: String
        let name: String
        var isCustom: Bool { id.hasPrefix(BackgroundLibrary.customPrefix) }
    }

    nonisolated static let presetPrefix = "preset:"
    nonisolated static let customPrefix = "custom:"
    nonisolated static let outputSize = CGSize(width: Int(VanishConstants.width), height: Int(VanishConstants.height))

    @Published private(set) var presets: [Item] = []
    @Published private(set) var custom: [Item] = []
    private var thumbnails: [String: NSImage] = [:]

    private let dir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Vanish/Backgrounds", isDirectory: true)
    }()

    init() {
        presets = Preset.all.map { Item(id: Self.presetPrefix + $0.key, name: $0.name) }
        reloadCustom()
    }

    var all: [Item] { presets + custom }

    func item(id: String?) -> Item? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }

    // MARK: Images

    /// Full-size (1280×720, aspect fill) image for the pipeline.
    func image(for id: String) -> CGImage? {
        if id.hasPrefix(Self.presetPrefix) {
            let key = String(id.dropFirst(Self.presetPrefix.count))
            return Preset.all.first(where: { $0.key == key })?.render(size: Self.outputSize)
        }
        guard id.hasPrefix(Self.customPrefix),
              let src = CGImageSourceCreateWithURL(fileURL(for: id) as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else { return nil }
        return Self.aspectFill(img, to: Self.outputSize)
    }

    func thumbnail(for id: String) -> NSImage? {
        if let t = thumbnails[id] { return t }
        guard let full = image(for: id),
              let small = Self.aspectFill(full, to: CGSize(width: 320, height: 180)) else { return nil }
        let t = NSImage(cgImage: small, size: NSSize(width: 160, height: 90))
        thumbnails[id] = t
        return t
    }

    // MARK: Custom images

    /// Copies an image file into the library. Returns the new item's id.
    func add(from url: URL) throws -> String {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceCreateImageAtIndex(src, 0, nil) != nil else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSURLErrorKey: url])
        }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension.lowercased()
        let base = url.deletingPathExtension().lastPathComponent
        var dest = dir.appendingPathComponent("\(base).\(ext)")
        var n = 2
        while FileManager.default.fileExists(atPath: dest.path) {
            dest = dir.appendingPathComponent("\(base) \(n).\(ext)")
            n += 1
        }
        try FileManager.default.copyItem(at: url, to: dest)
        reloadCustom()
        return Self.customPrefix + dest.lastPathComponent
    }

    func remove(id: String) {
        guard id.hasPrefix(Self.customPrefix) else { return }
        try? FileManager.default.removeItem(at: fileURL(for: id))
        thumbnails[id] = nil
        reloadCustom()
    }

    private func fileURL(for id: String) -> URL {
        dir.appendingPathComponent(String(id.dropFirst(Self.customPrefix.count)))
    }

    private func reloadCustom() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles])) ?? []
        custom = files
            .filter { UTType(filenameExtension: $0.pathExtension)?.conforms(to: .image) ?? false }
            .sorted {
                let a = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let b = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return a < b
            }
            .map { Item(id: Self.customPrefix + $0.lastPathComponent, name: $0.deletingPathExtension().lastPathComponent) }
    }

    // MARK: Helpers

    static func aspectFill(_ image: CGImage, to size: CGSize) -> CGImage? {
        let w = Int(size.width), h = Int(size.height)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                      | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        let iw = CGFloat(image.width), ih = CGFloat(image.height)
        let scale = max(size.width / iw, size.height / ih)
        let dw = iw * scale, dh = ih * scale
        ctx.draw(image, in: CGRect(x: (size.width - dw) / 2, y: (size.height - dh) / 2, width: dw, height: dh))
        return ctx.makeImage()
    }
}

// MARK: - Built-in presets

private struct Preset {
    struct Glow { let x, y, r: CGFloat; let color: UInt32; let alpha: CGFloat }

    let key: String
    let name: String
    /// Vertical gradient, bottom → top.
    let stops: [UInt32]
    let glows: [Glow]
    /// Soft bokeh discs: count and palette.
    let bokeh: Int
    let bokehColors: [UInt32]
    let vignette: CGFloat

    static let all: [Preset] = [
        Preset(key: "aurora", name: String(localized: "Aurora"),
               stops: [0x0A0718, 0x1B1140, 0x3B1E86],
               glows: [Glow(x: 0.3, y: 0.55, r: 0.55, color: 0x8B5CF6, alpha: 0.45),
                       Glow(x: 0.8, y: 0.75, r: 0.45, color: 0x22D3EE, alpha: 0.28)],
               bokeh: 40, bokehColors: [0xC4B5FD, 0x67E8F9], vignette: 0.35),
        Preset(key: "studio", name: String(localized: "Studio"),
               stops: [0x2B2D31, 0x55585E, 0x7A7E85],
               glows: [Glow(x: 0.5, y: 0.6, r: 0.6, color: 0xFFFFFF, alpha: 0.22)],
               bokeh: 0, bokehColors: [], vignette: 0.45),
        Preset(key: "sunset", name: String(localized: "Sunset"),
               stops: [0x3B1D4A, 0xC2556B, 0xF6A06A],
               glows: [Glow(x: 0.7, y: 0.35, r: 0.4, color: 0xFFD08A, alpha: 0.55)],
               bokeh: 18, bokehColors: [0xFFE2B8, 0xFFB199], vignette: 0.3),
        Preset(key: "ocean", name: String(localized: "Ocean"),
               stops: [0x03243A, 0x0B5A7A, 0x3BB3C9],
               glows: [Glow(x: 0.4, y: 0.9, r: 0.6, color: 0xB8F3FF, alpha: 0.35)],
               bokeh: 30, bokehColors: [0xB8F3FF, 0x7DD3FC], vignette: 0.35),
        Preset(key: "forest", name: String(localized: "Forest"),
               stops: [0x0C1F14, 0x23452C, 0x5C8A4E],
               glows: [Glow(x: 0.65, y: 0.8, r: 0.5, color: 0xE8F5B0, alpha: 0.3)],
               bokeh: 45, bokehColors: [0xE8F5B0, 0xA7D98B], vignette: 0.4),
        Preset(key: "midnight", name: String(localized: "Midnight"),
               stops: [0x020308, 0x0A1024, 0x182447],
               glows: [Glow(x: 0.5, y: 0.5, r: 0.5, color: 0x3B5BDB, alpha: 0.25)],
               bokeh: 60, bokehColors: [0xFFD27A, 0x8EA8FF, 0xFFFFFF], vignette: 0.5),
    ]

    func render(size: CGSize) -> CGImage? {
        let w = Int(size.width), h = Int(size.height)
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                      | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
            CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: a)
        }
        let locs = stops.indices.map { CGFloat($0) / CGFloat(max(1, stops.count - 1)) }
        let base = CGGradient(colorsSpace: cs, colors: stops.map { color($0) } as CFArray, locations: locs)!
        ctx.drawLinearGradient(base, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])

        let unit = max(size.width, size.height)
        for g in glows {
            let c = CGPoint(x: g.x * size.width, y: g.y * size.height)
            let grad = CGGradient(colorsSpace: cs, colors: [color(g.color, g.alpha), color(g.color, 0)] as CFArray,
                                  locations: [0, 1])!
            ctx.drawRadialGradient(grad, startCenter: c, startRadius: 0, endCenter: c, endRadius: g.r * unit, options: [])
        }

        var seed = UInt64(truncatingIfNeeded: key.hashValueStable)
        func rnd() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat((seed >> 33) & 0xFFFF) / CGFloat(0xFFFF)
        }
        for _ in 0..<bokeh {
            let c = CGPoint(x: rnd() * size.width, y: rnd() * size.height)
            let r = (0.008 + 0.035 * rnd() * rnd()) * unit
            let col = bokehColors[Int(rnd() * CGFloat(bokehColors.count)) % bokehColors.count]
            let a = 0.06 + 0.22 * rnd()
            let grad = CGGradient(colorsSpace: cs, colors: [color(col, a), color(col, a * 0.6), color(col, 0)] as CFArray,
                                  locations: [0, 0.7, 1])!
            ctx.drawRadialGradient(grad, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [])
        }

        if vignette > 0 {
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let grad = CGGradient(colorsSpace: cs, colors: [color(0, 0), color(0, vignette)] as CFArray,
                                  locations: [0.45, 1])!
            ctx.drawRadialGradient(grad, startCenter: c, startRadius: 0, endCenter: c,
                                   endRadius: unit * 0.62, options: [.drawsAfterEndLocation])
        }
        return ctx.makeImage()
    }
}

private extension String {
    /// FNV-1a: stable across launches (unlike `hashValue`).
    var hashValueStable: UInt64 {
        utf8.reduce(14695981039346656037) { ($0 ^ UInt64($1)) &* 1099511628211 }
    }
}
