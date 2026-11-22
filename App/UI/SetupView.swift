import AVFoundation
import SwiftUI

struct SetupView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var installer: ExtensionInstaller
    @State private var moveError: String?

    private var steps: [Bool] { model.setupSteps }
    private var doneCount: Int { steps.filter { $0 }.count }
    private var currentStep: Int { (steps.firstIndex(of: false) ?? steps.count) + 1 }

    var body: some View {
        VStack(spacing: 0) {
            hero
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    step(1, title: "Move Ghosted to Applications") {
                        Text("macOS installs camera extensions only from the Applications folder.")
                            .font(.callout).foregroundStyle(.secondary)
                        Button("Move and relaunch") { moveToApplications() }
                            .buttonStyle(.borderedProminent)
                        if let moveError { Text(moveError).font(.caption).foregroundStyle(.red) }
                    }

                    step(2, title: "Install Ghosted Camera") {
                        HStack {
                            Button("Install") { installer.activate() }
                                .buttonStyle(.borderedProminent)
                                .disabled(!installer.isInAppsFolder || installer.state == .installing)
                            installStateText
                        }
                        if !installer.isInAppsFolder {
                            Text("Finish step 1 first.").font(.caption).foregroundStyle(.secondary)
                        }
                        if installer.state == .needsApproval {
                            Callout(verbatim: approvalHint, systemImage: "lock.shield.fill", tint: Brand.violet)
                            Button("Open System Settings") { openApprovalSettings() }
                        }
                    }

                    step(3, title: "Give Ghosted access to the camera") {
                        Button("Allow") { model.requestCameraAccess() }
                            .buttonStyle(.borderedProminent)
                    }

                    step(4, title: "Capture your empty room or pick a background", keepContent: true) {
                        Text("Ghosted shows the empty room (or a picture) where you were. Capture the room with the camera where it will stay during calls, or pick a background.")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        BackgroundPicker(library: model.backgrounds)
                        Button {
                            model.selectBackground(nil)
                            model.mainTab = .studio
                        } label: {
                            Label(model.roomThumbnail == nil ? "Capture room in Studio…" : "Retake room in Studio…",
                                  systemImage: "camera.viewfinder")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(model.status.hasPlate ? .secondary : Brand.violet)
                        .disabled(!model.cameraAuthorized)
                    }

                    step(5, title: "Choose “Ghosted Camera” in your call app", keepContent: true) {
                        Text("Zoom: Settings → Video → Camera. Google Meet: Settings → Video. Teams: Settings → Devices. Telegram: Settings → Advanced → Video. FaceTime: Video menu.")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(18)
            }
            Divider()
            footer
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Toggle("Open Ghosted at login", isOn: Binding(get: { model.launchAtLogin },
                                                           set: { model.setLaunchAtLogin($0) }))
                .toggleStyle(.switch)
                .controlSize(.small)
                .help(Text("Recommended — otherwise call apps show “Open Ghosted” instead of your video."))
            Spacer()
            Text("\(doneCount) of \(steps.count) done")
                .font(.callout).foregroundStyle(.secondary).monospacedDigit()
            Button {
                settings.onboardingDone = true
                model.mainTab = .studio
            } label: {
                Text(model.essentialSetupDone ? "Go to Studio" : "Skip for now")
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(model.essentialSetupDone ? Brand.violet : .secondary)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            Brand.heroGradient
            DustField(count: 60, from: 0.7)
            HStack(spacing: 14) {
                AppIconView(size: 58)
                    .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.essentialSetupDone ? "You’re all set" : "Set up Ghosted")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("Ghosted adds a “Ghosted Camera” to your Mac. Pick it in Zoom, Meet, Teams, Telegram or FaceTime, then vanish with a shortcut, a snap or a “V” sign.")
                        .font(.callout)
                        .opacity(0.8)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 520, alignment: .leading)
                .foregroundStyle(.white)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.15))
                    Capsule()
                        .fill(LinearGradient(colors: [Brand.violet, Brand.cyan], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(6, geo.size.width * CGFloat(doneCount) / CGFloat(steps.count)))
                        .shadow(color: Brand.cyan.opacity(0.6), radius: 6)
                }
            }
            .frame(height: 5)
            .padding(.horizontal, 18)
            .padding(.bottom, 10)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: doneCount)
        }
        .frame(height: 118)
        .environment(\.colorScheme, .dark)
    }

    /// One setup step. Content of finished steps is hidden unless `keepContent`.
    @ViewBuilder
    private func step<Content: View>(_ n: Int, title: LocalizedStringKey, keepContent: Bool = false,
                                     @ViewBuilder content: () -> Content) -> some View {
        let done = steps[n - 1]
        let current = n == currentStep
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(done ? AnyShapeStyle(Color.green) : current ? AnyShapeStyle(Brand.vanishGradient)
                                                                     : AnyShapeStyle(.quaternary))
                if done {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                } else {
                    Text("\(n)").font(.system(size: 13, weight: .bold, design: .rounded))
                }
            }
            .foregroundStyle(done || current ? Color.white : Color.secondary)
            .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(done && !current ? Color.secondary : Color.primary)
                    .padding(.top, 3)
                if !done || keepContent {
                    content()
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(current ? AnyShapeStyle(Brand.violet.opacity(0.08)) : AnyShapeStyle(.quaternary.opacity(0.35)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(current ? Brand.violet.opacity(0.45) : .clear, lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.2), value: done)
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
            return String(localized: "Open System Settings → General → Login Items & Extensions → Camera Extensions and turn on Ghosted.")
        }
        return String(localized: "Open System Settings → Privacy & Security, scroll down and click “Allow” next to the message about Ghosted.")
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
