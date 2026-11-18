#!/usr/bin/env swift
// Generates Ghosted's app icon, menu-bar template icons and accent color into
// App/Assets.xcassets. Deterministic: same output on every run.
//
//   swift Tools/make-icons.swift
//
// Concept: a person bust inside a camera viewfinder; the right side of the
// figure breaks into square chips of dust that drift up and away.

import AppKit
import CoreGraphics
import Foundation
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath)
let assets = root.appendingPathComponent("App/Assets.xcassets")

// MARK: - Helpers

struct RNG {
    var state: UInt64
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double((state >> 33) & 0xFFFFFF) / Double(0xFFFFFF)
    }
    mutating func range(_ a: Double, _ b: Double) -> CGFloat { CGFloat(a + (b - a) * next()) }
}

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func mix(_ a: CGColor, _ b: CGColor, _ t: CGFloat) -> CGColor {
    let ca = a.components!, cb = b.components!
    let t = max(0, min(1, t))
    return CGColor(srgbRed: ca[0] + (cb[0] - ca[0]) * t, green: ca[1] + (cb[1] - ca[1]) * t,
                   blue: ca[2] + (cb[2] - ca[2]) * t, alpha: ca[3] + (cb[3] - ca[3]) * t)
}

func makeContext(_ size: Int) -> CGContext {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high
    return ctx
}

func writePNG(_ image: CGImage, to url: URL) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

func resize(_ image: CGImage, to size: Int) -> CGImage {
    let ctx = makeContext(size)
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    return ctx.makeImage()!
}

func writeJSON(_ object: Any, to url: URL) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    try! data.write(to: url)
}

/// Person bust in a unit space where the canvas is `s` wide. Origin bottom-left.
func bustPath(scale s: CGFloat, cx: CGFloat, base: CGFloat) -> CGPath {
    let p = CGMutablePath()
    // Shoulders.
    let w = 205 * s, top = base + 222 * s
    p.move(to: CGPoint(x: cx - w, y: base))
    p.addCurve(to: CGPoint(x: cx, y: top),
               control1: CGPoint(x: cx - w, y: base + 150 * s),
               control2: CGPoint(x: cx - w * 0.52, y: top))
    p.addCurve(to: CGPoint(x: cx + w, y: base),
               control1: CGPoint(x: cx + w * 0.52, y: top),
               control2: CGPoint(x: cx + w, y: base + 150 * s))
    p.closeSubpath()
    // Head.
    let r = 112 * s
    p.addEllipse(in: CGRect(x: cx - r, y: top + 30 * s, width: r * 2, height: r * 2))
    return p
}

func brackets(in ctx: CGContext, rect: CGRect, length: CGFloat, width: CGFloat) {
    ctx.setLineWidth(width)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    let (x0, y0, x1, y1) = (rect.minX, rect.minY, rect.maxX, rect.maxY)
    for (corner, dx, dy) in [(CGPoint(x: x0, y: y0), 1.0, 1.0), (CGPoint(x: x1, y: y0), -1.0, 1.0),
                             (CGPoint(x: x0, y: y1), 1.0, -1.0), (CGPoint(x: x1, y: y1), -1.0, -1.0)] {
        ctx.move(to: CGPoint(x: corner.x, y: corner.y + dy * length))
        ctx.addLine(to: corner)
        ctx.addLine(to: CGPoint(x: corner.x + dx * length, y: corner.y))
    }
    ctx.strokePath()
}

// MARK: - App icon (1024 master)

func appIcon() -> CGImage {
    let S = 1024
    let ctx = makeContext(S)
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // Drop shadow under the tile (macOS icon grid).
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: rgb(0x000000, 0.35))
    ctx.addPath(tilePath)
    ctx.setFillColor(rgb(0x120C2B))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()

    // Background: deep violet night.
    let bg = CGGradient(colorsSpace: nil, colors: [rgb(0x0A0718), rgb(0x1B1140), rgb(0x3B1E86)] as CFArray,
                        locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
    func glow(_ c: CGPoint, _ r: CGFloat, _ color: CGColor) {
        let g = CGGradient(colorsSpace: nil, colors: [color, color.copy(alpha: 0)!] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [])
    }
    glow(CGPoint(x: 440, y: 520), 400, rgb(0x8B5CF6, 0.55))
    glow(CGPoint(x: 760, y: 680), 330, rgb(0x22D3EE, 0.30))
    glow(CGPoint(x: 512, y: 960), 300, rgb(0xC084FC, 0.25))

    // Viewfinder brackets.
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.28))
    brackets(in: ctx, rect: CGRect(x: 214, y: 214, width: 596, height: 596), length: 92, width: 20)

    // Figure + dissolve.
    let cx: CGFloat = 440, base: CGFloat = 232
    let figure = bustPath(scale: 0.92, cx: cx, base: base)
    let box = figure.boundingBoxOfPath
    let cell: CGFloat = 17
    var rng = RNG(state: 0xC0FFEE)
    var solid: [CGRect] = []
    struct Chip { var rect: CGRect; var angle: CGFloat; var t: CGFloat }
    var chips: [Chip] = []

    var y = box.minY
    while y < box.maxY {
        var x = box.minX
        while x < box.maxX {
            let c = CGPoint(x: x + cell / 2, y: y + cell / 2)
            let corners = [c, CGPoint(x: x, y: y), CGPoint(x: x + cell, y: y),
                           CGPoint(x: x, y: y + cell), CGPoint(x: x + cell, y: y + cell)]
            if corners.contains(where: { figure.contains($0) }) {
                let noise = sin(c.x * 0.043) * 0.5 + sin(c.y * 0.061 + c.x * 0.017) * 0.5
                let d = (c.x - 438) / 175 + noise * 0.22 + (c.y - 400) / 1600
                if !figure.contains(c) {
                    // Edge cell: keeps the outline smooth on the solid side only.
                    if d < 0.15 { solid.append(CGRect(x: x, y: y, width: cell, height: cell)) }
                } else if CGFloat(rng.next()) > d {
                    solid.append(CGRect(x: x, y: y, width: cell, height: cell))
                } else {
                    let a = min(max(d, 0), 1.25)
                    let size = cell * rng.range(0.35, 0.92)
                    let dx = a * rng.range(30, 250)
                    let dy = a * rng.range(-10, 190)
                    chips.append(Chip(rect: CGRect(x: c.x + dx - size / 2, y: c.y + dy - size / 2,
                                                   width: size, height: size),
                                      angle: rng.range(-0.6, 0.6), t: a))
                }
            }
            x += cell
        }
        y += cell
    }

    let bodyGradient = CGGradient(colorsSpace: nil, colors: [rgb(0xFFFFFF), rgb(0xE9E1FF), rgb(0xC9B8FF)] as CFArray,
                                  locations: [0, 0.6, 1])!

    // Solid part of the figure, with a soft glow.
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 46, color: rgb(0xA78BFA, 0.65))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.addPath(figure)
    ctx.clip()
    ctx.addRects(solid)
    ctx.clip()
    ctx.drawLinearGradient(bodyGradient, start: CGPoint(x: 300, y: 820), end: CGPoint(x: 600, y: 214), options: [])
    ctx.endTransparencyLayer()
    ctx.restoreGState()

    // Dust chips.
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 14, color: rgb(0x8B5CF6, 0.8))
    for chip in chips {
        let col = chip.t < 0.6
            ? mix(rgb(0xF4F0FF), rgb(0xC4B5FD), chip.t / 0.6)
            : mix(rgb(0xC4B5FD), rgb(0x67E8F9), (chip.t - 0.6) / 0.65)
        let alpha = max(0.18, min(1, 1.08 - chip.t * 0.62))
        ctx.saveGState()
        ctx.translateBy(x: chip.rect.midX, y: chip.rect.midY)
        ctx.rotate(by: chip.angle)
        ctx.setFillColor(col.copy(alpha: alpha)!)
        let r = CGRect(x: -chip.rect.width / 2, y: -chip.rect.height / 2, width: chip.rect.width, height: chip.rect.height)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: r.width * 0.18, cornerHeight: r.width * 0.18, transform: nil))
        ctx.fillPath()
        ctx.restoreGState()
    }
    // Fine specks drifting further away.
    for _ in 0..<95 {
        let t = rng.range(0, 1)
        let p = CGPoint(x: 590 + t * 280 + rng.range(-40, 40), y: 420 + t * 300 + rng.range(-150, 150))
        let r = rng.range(1.5, 5) * (1 - t * 0.4)
        ctx.setFillColor(mix(rgb(0xDDD6FE), rgb(0x67E8F9), t).copy(alpha: rng.range(0.15, 0.7) * (1 - t * 0.5))!)
        ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
    }
    ctx.restoreGState()

    // Glassy top highlight + hairline border.
    let sheen = CGGradient(colorsSpace: nil, colors: [rgb(0xFFFFFF, 0.10), rgb(0xFFFFFF, 0)] as CFArray,
                           locations: [0, 1])!
    ctx.drawLinearGradient(sheen, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 620), options: [])
    ctx.restoreGState()

    ctx.addPath(tilePath)
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.10))
    ctx.setLineWidth(3)
    ctx.strokePath()
    return ctx.makeImage()!
}

// MARK: - Menu-bar template icons (18 pt)

func menuIcon(px: Int, hidden: Bool) -> CGImage {
    let ctx = makeContext(px)
    let k = CGFloat(px) / 36 // design in a 36-unit grid
    ctx.scaleBy(x: k, y: k)
    ctx.setStrokeColor(rgb(0x000000))
    ctx.setFillColor(rgb(0x000000))
    brackets(in: ctx, rect: CGRect(x: 2.5, y: 2.5, width: 31, height: 31), length: 7, width: 2.6)

    let figure = bustPath(scale: 0.052, cx: 18, base: 6.5)
    if !hidden {
        ctx.addPath(figure)
        ctx.fillPath()
    } else {
        // Ghost: left part solid, right part dust.
        ctx.saveGState()
        ctx.addPath(figure)
        ctx.clip()
        ctx.fill(CGRect(x: 0, y: 0, width: 16.2, height: 36))
        ctx.restoreGState()
        let dots: [(CGFloat, CGFloat, CGFloat)] = [
            (19.0, 9.0, 1.5), (21.5, 13.0, 1.4), (23.5, 8.5, 1.3), (19.6, 21.5, 1.5), (22.5, 24.5, 1.3),
            (25.5, 17.0, 1.2), (26.8, 11.0, 1.1), (27.5, 22.5, 1.0), (29.5, 15.5, 0.9), (24.0, 28.0, 1.0),
        ]
        for (x, y, r) in dots {
            ctx.fill(CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
        }
    }
    return ctx.makeImage()!
}

// MARK: - Write asset catalog

writeJSON(["info": ["author": "xcode", "version": 1]], to: assets.appendingPathComponent("Contents.json"))

let master = appIcon()
writePNG(master, to: root.appendingPathComponent("Tools/AppIcon-1024.png"))
let iconSet = assets.appendingPathComponent("AppIcon.appiconset")
var images: [[String: String]] = []
for pt in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(pt)x\(pt)\(scale == 2 ? "@2x" : "").png"
        writePNG(resize(master, to: pt * scale), to: iconSet.appendingPathComponent(name))
        images.append(["filename": name, "idiom": "mac", "scale": "\(scale)x", "size": "\(pt)x\(pt)"])
    }
}
writeJSON(["images": images, "info": ["author": "xcode", "version": 1]],
          to: iconSet.appendingPathComponent("Contents.json"))

for (name, hidden) in [("MenuBarIcon", false), ("MenuBarIconHidden", true)] {
    let set = assets.appendingPathComponent("\(name).imageset")
    writePNG(menuIcon(px: 18, hidden: hidden), to: set.appendingPathComponent("\(name).png"))
    writePNG(menuIcon(px: 36, hidden: hidden), to: set.appendingPathComponent("\(name)@2x.png"))
    writeJSON([
        "images": [["filename": "\(name).png", "idiom": "universal", "scale": "1x"],
                   ["filename": "\(name)@2x.png", "idiom": "universal", "scale": "2x"]],
        "info": ["author": "xcode", "version": 1],
        "properties": ["template-rendering-intent": "template"],
    ], to: set.appendingPathComponent("Contents.json"))
}

func colorJSON(_ r: Int, _ g: Int, _ b: Int) -> [String: Any] {
    ["color-space": "srgb", "components": ["red": "\(r)", "green": "\(g)", "blue": "\(b)", "alpha": "1.000"]]
}
writeJSON([
    "colors": [
        ["idiom": "universal", "color": colorJSON(124, 92, 255)],
        ["idiom": "universal", "color": colorJSON(157, 133, 255),
         "appearances": [["appearance": "luminosity", "value": "dark"]]],
    ],
    "info": ["author": "xcode", "version": 1],
], to: assets.appendingPathComponent("AccentColor.colorset/Contents.json"))

print("Icons written to \(assets.path)")
