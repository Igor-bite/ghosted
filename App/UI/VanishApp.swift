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

        Window(Brand.name, id: WindowID.main) {
            MainWindow()
                .environmentObject(model)
                .environmentObject(model.settings)
                .environmentObject(model.installer)
        }
        .windowResizability(.contentSize)
    }
}

enum WindowID {
    static let main = "main"
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
                #if DEBUG
                if UserDefaults.standard.string(forKey: "snapshotDir") != nil {
                    Snapshotter.runIfRequested()
                    return
                }
                #endif
                if !settings.onboardingDone {
                    OpenMainAction(openWindow: openWindow, model: model)(.setup)
                }
            }
    }
}
