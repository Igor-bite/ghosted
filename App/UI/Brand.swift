import AppKit
import SwiftUI

/// Product name and visual language shared by all windows.
enum Brand {
    static let name = "Ghosted"
    static let cameraName = VanishConstants.deviceName

    static let violet = Color(red: 124 / 255, green: 92 / 255, blue: 255 / 255)
    static let orchid = Color(red: 176 / 255, green: 108 / 255, blue: 255 / 255)
    static let cyan = Color(red: 34 / 255, green: 211 / 255, blue: 238 / 255)
    static let night = Color(red: 18 / 255, green: 12 / 255, blue: 43 / 255)

    static let vanishGradient = LinearGradient(colors: [violet, orchid],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)
    static let appearGradient = LinearGradient(colors: [cyan.opacity(0.9), violet],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)
    static let heroGradient = LinearGradient(
        colors: [Color(red: 0.23, green: 0.12, blue: 0.53), Color(red: 0.11, green: 0.07, blue: 0.25), night],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }
}

/// The app icon as a SwiftUI view.
struct AppIconView: View {
    var size: CGFloat = 40
    var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}

/// Large gradient call-to-action used for Vanish / Appear.
struct HeroButtonStyle: ButtonStyle {
    var hidden: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(hidden ? Brand.appearGradient : Brand.vanishGradient)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                    )
                    .shadow(color: Brand.violet.opacity(isEnabled ? 0.45 : 0), radius: 10, y: 4)
            }
            .opacity(isEnabled ? 1 : 0.45)
            .saturation(isEnabled ? 1 : 0.2)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Keyboard shortcut rendered as a small key cap.
struct KeyCap: View {
    let text: String
    var onDark = false
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .monospaced()
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(onDark ? AnyShapeStyle(.white.opacity(0.9)) : AnyShapeStyle(.secondary))
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(onDark ? AnyShapeStyle(.white.opacity(0.18)) : AnyShapeStyle(.quaternary))
            )
    }
}

/// Rounded grouped surface.
struct Card<Content: View>: View {
    var padding: CGFloat = 12
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.quaternary.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.primary.opacity(0.06), lineWidth: 1)
            )
    }
}

/// Tinted inline notice (warnings, errors, hints).
struct Callout: View {
    let text: Text
    let systemImage: String
    let tint: Color

    init(text: LocalizedStringKey, systemImage: String = "exclamationmark.triangle.fill", tint: Color = .orange) {
        self.text = Text(text)
        self.systemImage = systemImage
        self.tint = tint
    }

    init(verbatim: String, systemImage: String = "exclamationmark.triangle.fill", tint: Color = .orange) {
        self.text = Text(verbatim: verbatim)
        self.systemImage = systemImage
        self.tint = tint
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: systemImage).foregroundStyle(tint)
            text.fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint.opacity(0.12)))
    }
}

/// Small colored status capsule.
struct StatusPill: View {
    let text: String
    let color: Color
    var pulsing = false
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                if pulsing {
                    Circle().fill(color.opacity(0.35))
                        .frame(width: 14, height: 14)
                        .scaleEffect(pulse ? 1 : 0.4)
                        .opacity(pulse ? 0 : 1)
                }
                Circle().fill(color).frame(width: 7, height: 7)
            }
            .frame(width: 10, height: 10)
            Text(text).lineLimit(1)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.14)))
        .onAppear {
            guard pulsing else { return }
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}

/// Decorative drifting dust, used behind headers.
struct DustField: View {
    var count = 70
    /// Horizontal band (0…1) the dust occupies.
    var from: CGFloat = 0.45
    var body: some View {
        Canvas { ctx, size in
            var seed: UInt64 = 0x9E3779B97F4A7C15
            func rnd() -> CGFloat {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return CGFloat((seed >> 33) & 0xFFFF) / CGFloat(0xFFFF)
            }
            for _ in 0..<count {
                let t = rnd()
                let x = size.width * (from + (1 - from) * t)
                let y = size.height * (0.1 + 0.8 * rnd())
                let r = (1 + 2.5 * rnd()) * (1 - t * 0.4)
                let color = t < 0.5 ? Color(red: 0.86, green: 0.82, blue: 1) : Brand.cyan
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 2)),
                         with: .color(color.opacity(Double(0.15 + 0.5 * rnd()))))
            }
        }
        .allowsHitTesting(false)
    }
}
