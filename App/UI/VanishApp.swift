import SwiftUI

@main
struct VanishApp: App {
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(model)
                .environmentObject(model.settings)
                .environmentObject(model.installer)
        } label: {
            MenuBarLabel()
                .environmentObject(model)
                .environmentObject(model.settings)
        }
        .menuBarExtraStyle(.window)

        Window(String(localized: "Preview & Room"), id: WindowID.preview) {
            PreviewWindow()
                .environmentObject(model)
                .environmentObject(model.settings)
        }
        .windowResizability(.contentSize)

        Window(String(localized: "Welcome to Ghosted"), id: WindowID.onboarding) {
            OnboardingView()
                .environmentObject(model)
                .environmentObject(model.settings)
                .environmentObject(model.installer)
        }
        .windowResizability(.contentSize)

        Window(String(localized: "Ghosted Settings"), id: WindowID.settings) {
            SettingsView()
                .environmentObject(model)
                .environmentObject(model.settings)
                .environmentObject(model.installer)
        }
        .windowResizability(.contentSize)
    }
}

enum WindowID {
    static let preview = "preview"
    static let onboarding = "onboarding"
    static let settings = "settings"
}

/// Opens a window and brings the (accessory) app to front.
@MainActor
func bringToFront() {
    NSApp.activate(ignoringOtherApps: true)
}

struct MenuBarLabel: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: AppSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(model.status.targetHidden ? "MenuBarIconHidden" : "MenuBarIcon")
            .renderingMode(.template)
            .task {
                if !settings.onboardingDone {
                    openWindow(id: WindowID.onboarding)
                    bringToFront()
                }
            }
    }
}
