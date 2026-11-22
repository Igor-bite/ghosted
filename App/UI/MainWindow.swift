import SwiftUI

/// Tabs of the single main window.
enum MainTab: String, CaseIterable, Identifiable {
    case setup, studio, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .setup: return String(localized: "Setup")
        case .studio: return String(localized: "Studio")
        case .settings: return String(localized: "Settings")
        }
    }

    var systemImage: String {
        switch self {
        case .setup: return "list.bullet.clipboard"
        case .studio: return "rectangle.inset.filled.and.person.filled"
        case .settings: return "gearshape"
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .setup: return "1"
        case .studio: return "2"
        case .settings: return "3"
        }
    }
}

extension AppModel {
    /// Setup checklist, in order: in /Applications, camera installed, camera access, room/background, used in a call.
    var setupSteps: [Bool] {
        [installer.isInAppsFolder, devicePresent, cameraAuthorized, status.hasPlate, (clients?.count ?? 0) > 0]
    }

    /// The first four steps are needed to vanish; the last one happens in the call app.
    var essentialSetupDone: Bool { setupSteps.prefix(4).allSatisfy { $0 } }
}

/// Opens the main window on a tab and brings the app forward.
struct OpenMainAction {
    let openWindow: OpenWindowAction
    let model: AppModel

    @MainActor
    func callAsFunction(_ tab: MainTab) {
        model.mainTab = tab
        openWindow(id: WindowID.main)
        bringToFront()
    }
}

/// The main window: setup guide, live studio and settings in one place.
struct MainWindow: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var installer: ExtensionInstaller

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            Group {
                switch model.mainTab {
                case .setup: SetupView()
                case .studio: StudioView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 760, height: 580)
        .tint(Brand.violet)
    }

    private var tabBar: some View {
        HStack(spacing: 10) {
            AppIconView(size: 26)
                .frame(width: 150, alignment: .leading)

            Spacer(minLength: 0)
            segmented
            Spacer(minLength: 0)

            StatusPill(text: model.devicePresent ? String(localized: "Camera installed")
                                                 : String(localized: "Not installed"),
                       color: model.devicePresent ? .green : .gray)
                .fixedSize()
                .frame(width: 150, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.bar)
    }

    private var segmented: some View {
        HStack(spacing: 2) {
            ForEach(MainTab.allCases) { tab in
                let selected = model.mainTab == tab
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { model.mainTab = tab }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.systemImage).font(.system(size: 12, weight: .semibold))
                        Text(tab.title).font(.callout.weight(.medium)).lineLimit(1).fixedSize()
                        if tab == .setup { setupBadge(selected: selected) }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .foregroundStyle(selected ? Color.white : Color.primary)
                    .background {
                        if selected { Capsule().fill(Brand.vanishGradient) }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(tab.shortcut, modifiers: .command)
                .help(Text("\(tab.title) (⌘\(String(tab.shortcut.character)))"))
            }
        }
        .padding(3)
        .background(Capsule().fill(.quaternary.opacity(0.6)))
    }

    @ViewBuilder
    private func setupBadge(selected: Bool) -> some View {
        let steps = model.setupSteps
        let done = steps.filter { $0 }.count
        if model.essentialSetupDone {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(selected ? Color.white : Color.green)
        } else {
            Text(verbatim: "\(done)/\(steps.count)")
                .font(.caption2.weight(.bold)).monospacedDigit()
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule().fill(selected ? Color.white.opacity(0.25) : Color.orange.opacity(0.25)))
        }
    }
}
