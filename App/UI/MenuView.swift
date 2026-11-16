import SwiftUI

struct MenuView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var installer: ExtensionInstaller
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            if !model.devicePresent {
                installHint
            }
            Button {
                model.toggle()
            } label: {
                Label(model.status.targetHidden ? "Appear" : "Vanish",
                      systemImage: model.status.targetHidden ? "person.fill" : "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(!model.status.hasPlate && !model.status.targetHidden)
            .help(Text("Shortcut: \(settings.shortcut.display)"))

            HStack {
                Text("Shortcut")
                Spacer()
                Text(settings.shortcut.display).foregroundStyle(.secondary).monospaced()
            }
            .font(.callout)

            if !model.status.hasPlate {
                Label("Capture the empty room to enable vanishing.", systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.orange)
            } else if model.status.plateCameraMismatch {
                Label("Room snapshot was taken with another camera.", systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.orange)
            }

            Picker("Camera", selection: Binding(get: { settings.cameraID ?? "" },
                                                set: { model.selectCamera($0.isEmpty ? nil : $0) })) {
                Text("System default").tag("")
                ForEach(model.cameras) { Text($0.name).tag($0.id) }
            }

            Toggle("Dust effect", isOn: $settings.dustEnabled)
            Toggle("Vanish on finger snap", isOn: Binding(get: { settings.snapEnabled },
                                                           set: { model.setSnapEnabled($0) }))
            Toggle("Vanish on “V” gesture", isOn: $settings.vSignEnabled)

            if let msg = model.message {
                Text(msg).font(.callout).foregroundStyle(.red)
            }

            Divider()
            HStack {
                Button("Preview & Room…") { open(WindowID.preview) }
                Spacer()
                Button("Settings…") { open(WindowID.settings) }
            }
            HStack {
                Button("Setup guide…") { open(WindowID.onboarding) }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 300)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text("Vanish Camera").font(.headline)
                Text(statusText).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var installHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Vanish Camera is not installed yet.", systemImage: "video.slash")
                .font(.callout)
            Button("Open setup guide") { open(WindowID.onboarding) }
        }
    }

    private var statusColor: Color {
        if !model.devicePresent { return .gray }
        if let n = model.clients?.count, n > 0 { return model.status.targetHidden ? .purple : .green }
        return .secondary
    }

    private var statusText: String {
        if !model.devicePresent { return String(localized: "Not installed") }
        if let name = model.consumerName {
            return String(localized: "In use by \(name)")
        }
        if let n = model.clients?.count, n > 0 { return String(localized: "In use") }
        return String(localized: "Not in use — select “Vanish Camera” in your call app")
    }

    private func open(_ id: String) {
        openWindow(id: id)
        bringToFront()
    }
}
