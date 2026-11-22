import Foundation

/// How the person vanishes and appears.
enum EffectStyle: String, CaseIterable, Identifiable {
    /// Crumbles into drifting dust.
    case dust
    /// Breaks into jittering digital blocks.
    case glitch
    /// A glowing scan line sweeps the person away (and back, bottom-up).
    case beam
    /// Plain crossfade.
    case fade

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dust: return String(localized: "Dust")
        case .glitch: return String(localized: "Glitch")
        case .beam: return String(localized: "Beam")
        case .fade: return String(localized: "Fade")
        }
    }

    var subtitle: String {
        switch self {
        case .dust: return String(localized: "Crumble into drifting dust")
        case .glitch: return String(localized: "Break up into digital noise")
        case .beam: return String(localized: "Teleport with a scan line")
        case .fade: return String(localized: "Soft, calm crossfade")
        }
    }

    var systemImage: String {
        switch self {
        case .dust: return "aqi.medium"
        case .glitch: return "waveform"
        case .beam: return "wand.and.rays"
        case .fade: return "circle.lefthalf.filled"
        }
    }
}

/// User preferences persisted in UserDefaults.
@MainActor
final class AppSettings: ObservableObject {
    private let d = UserDefaults.standard

    @Published var cameraID: String? { didSet { d.set(cameraID, forKey: "cameraID") } }
    @Published var effectStyle: EffectStyle { didSet { d.set(effectStyle.rawValue, forKey: "effectStyle") } }
    /// false = full replacement with the room snapshot (default), true = live room (hybrid).
    @Published var hybridRoom: Bool { didSet { d.set(hybridRoom, forKey: "hybridRoom") } }
    /// Virtual background id (see BackgroundLibrary); nil = empty-room snapshot from the camera.
    @Published var backgroundID: String? { didSet { d.set(backgroundID, forKey: "backgroundID") } }
    @Published var effectDuration: Double { didSet { d.set(effectDuration, forKey: "effectDuration") } }
    @Published var snapEnabled: Bool { didSet { d.set(snapEnabled, forKey: "snapEnabled") } }
    @Published var snapThreshold: Double { didSet { d.set(snapThreshold, forKey: "snapThreshold") } }
    @Published var vSignEnabled: Bool { didSet { d.set(vSignEnabled, forKey: "vSignEnabled") } }
    @Published var onboardingDone: Bool { didSet { d.set(onboardingDone, forKey: "onboardingDone") } }
    @Published var lastHidden: Bool { didSet { d.set(lastHidden, forKey: "lastHidden") } }
    @Published var shortcut: Shortcut {
        didSet { d.set(try? JSONEncoder().encode(shortcut), forKey: "shortcut") }
    }

    init() {
        d.register(defaults: [
            "dustEnabled": true,
            "hybridRoom": false,
            "effectDuration": 1.8,
            "snapEnabled": false,
            "snapThreshold": 0.8,
            "vSignEnabled": false,
            "onboardingDone": false,
            "lastHidden": false,
        ])
        cameraID = d.string(forKey: "cameraID")
        if let raw = d.string(forKey: "effectStyle"), let style = EffectStyle(rawValue: raw) {
            effectStyle = style
        } else {
            // 0.1 had a single dust on/off switch; "off" meant a crossfade.
            effectStyle = d.bool(forKey: "dustEnabled") ? .dust : .fade
        }
        hybridRoom = d.bool(forKey: "hybridRoom")
        backgroundID = d.string(forKey: "backgroundID")
        effectDuration = min(3, max(1, d.double(forKey: "effectDuration")))
        snapEnabled = d.bool(forKey: "snapEnabled")
        snapThreshold = d.double(forKey: "snapThreshold")
        vSignEnabled = d.bool(forKey: "vSignEnabled")
        onboardingDone = d.bool(forKey: "onboardingDone")
        lastHidden = d.bool(forKey: "lastHidden")
        if let data = d.data(forKey: "shortcut"), let s = try? JSONDecoder().decode(Shortcut.self, from: data), s.isAllowed {
            shortcut = s
        } else {
            shortcut = .default
        }
    }
}
