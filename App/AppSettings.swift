import Foundation

/// User preferences persisted in UserDefaults.
@MainActor
final class AppSettings: ObservableObject {
    private let d = UserDefaults.standard

    @Published var cameraID: String? { didSet { d.set(cameraID, forKey: "cameraID") } }
    @Published var dustEnabled: Bool { didSet { d.set(dustEnabled, forKey: "dustEnabled") } }
    @Published var hybridRoom: Bool { didSet { d.set(hybridRoom, forKey: "hybridRoom") } }
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
            "hybridRoom": true,
            "effectDuration": 1.8,
            "snapEnabled": false,
            "snapThreshold": 0.8,
            "vSignEnabled": false,
            "onboardingDone": false,
            "lastHidden": false,
        ])
        cameraID = d.string(forKey: "cameraID")
        dustEnabled = d.bool(forKey: "dustEnabled")
        hybridRoom = d.bool(forKey: "hybridRoom")
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
