import AVFoundation
import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var installer: ExtensionInstaller
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @State private var moveError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Set up Vanish").font(.largeTitle.bold())
            Text("Vanish adds a “Vanish Camera” to your Mac. Pick it in Zoom, Meet, Teams, Telegram or FaceTime, then vanish in a cloud of dust with a shortcut, a snap or a “V” sign.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            step(1, done: installer.isInAppsFolder, title: "Move Vanish to Applications") {
                if !installer.isInAppsFolder {
                    Button("Move and relaunch") { moveToApplications() }
                    if let moveError { Text(moveError).font(.caption).foregroundStyle(.red) }
                }
            }

            step(2, done: model.devicePresent, title: "Install Vanish Camera") {
                if !model.devicePresent {
                    HStack {
                        Button("Install") { installer.activate() }
                            .disabled(!installer.isInAppsFolder || installer.state == .installing)
                        installStateText
                    }
                    if installer.state == .needsApproval {
                        Text(approvalHint).font(.callout).fixedSize(horizontal: false, vertical: true)
                        Button("Open System Settings") { openApprovalSettings() }
                    }
                }
            }

            step(3, done: model.cameraAuthorized, title: "Allow camera access") {
                if !model.cameraAuthorized {
                    Button("Allow") { model.requestCameraAccess() }
                }
            }

            step(4, done: model.status.hasPlate, title: "Capture your empty room") {
                Button(model.status.hasPlate ? "Retake…" : "Open preview…") {
                    openWindow(id: WindowID.preview)
                    bringToFront()
                }
                .disabled(!model.cameraAuthorized)
            }

            step(5, done: (model.clients?.count ?? 0) > 0, title: "Choose “Vanish Camera” in your call app") {
                Text("Zoom: Settings → Video → Camera. Google Meet: Settings → Video. Teams: Settings → Devices. Telegram: Settings → Advanced → Video. FaceTime: Video menu.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Toggle("Open Vanish at login (recommended — otherwise call apps show “Open Vanish”)",
                   isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))

            HStack {
                Spacer()
                Button("Done") {
                    settings.onboardingDone = true
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560)
    }

    @ViewBuilder
    private func step<Content: View>(_ n: Int, done: Bool, title: LocalizedStringKey,
                                     @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "\(n).circle")
                .font(.title2)
                .foregroundStyle(done ? .green : .secondary)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                content()
            }
        }
    }

    @ViewBuilder private var installStateText: some View {
        switch installer.state {
        case .installing: ProgressView().controlSize(.small)
        case .failed(let msg): Text(msg).font(.caption).foregroundStyle(.red)
        case .removed: Text("Removed").font(.caption).foregroundStyle(.secondary)
        default: EmptyView()
        }
    }

    private var approvalHint: String {
        if #available(macOS 15, *) {
            return String(localized: "Open System Settings → General → Login Items & Extensions → Camera Extensions and turn on Vanish.")
        }
        return String(localized: "Open System Settings → Privacy & Security, scroll down and click “Allow” next to the message about Vanish.")
    }

    private func openApprovalSettings() {
        let url: URL
        if #available(macOS 15, *) {
            url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!
        } else {
            url = URL(string: "x-apple.systempreferences:com.apple.preference.security?General")!
        }
        NSWorkspace.shared.open(url)
    }

    private func moveToApplications() {
        let src = Bundle.main.bundleURL
        let dst = URL(fileURLWithPath: "/Applications").appendingPathComponent(src.lastPathComponent)
        do {
            if FileManager.default.fileExists(atPath: dst.path) {
                try FileManager.default.trashItem(at: dst, resultingItemURL: nil)
            }
            try FileManager.default.copyItem(at: src, to: dst)
            let config = NSWorkspace.OpenConfiguration()
            config.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: dst, configuration: config) { _, _ in
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }
        } catch {
            moveError = error.localizedDescription
        }
    }
}
