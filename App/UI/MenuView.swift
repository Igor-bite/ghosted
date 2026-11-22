import SwiftUI

struct MenuView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var installer: ExtensionInstaller
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if !model.devicePresent {
                installHint
            } else {
                heroButton
                notices
            }

            Card(padding: 4) {
                VStack(spacing: 0) {
                    row("camera.fill") {
                        Picker("Camera", selection: Binding(get: { settings.cameraID ?? "" },
                                                            set: { model.selectCamera($0.isEmpty ? nil : $0) })) {
                            Text("System default").tag("")
                            ForEach(model.cameras) { Text($0.name).tag($0.id) }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 160)
                    } label: { Text("Camera").fixedSize() }
                    Divider().padding(.leading, 38)
                    row("photo.fill") {
                        BackgroundMenu(library: model.backgrounds) { open(.settings) }
                            .frame(maxWidth: 160, alignment: .trailing)
                    } label: { Text("Background").fixedSize() }
                    if settings.backgroundID == nil {
                        Divider().padding(.leading, 38)
                        row("square.on.square.dashed") {
                            Picker("Room mode", selection: $settings.hybridRoom) {
                                Text("Full").tag(false)
                                Text("Live").tag(true)
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 130)
                            .help(Text(settings.hybridRoom
                                       ? "Live room: lights and windows keep moving; a faint outline may remain."
                                       : "Full replacement: the whole frame is the room snapshot."))
                        } label: { Text("Room mode").fixedSize() }
                    }
                    Divider().padding(.leading, 38)
                    row(settings.effectStyle.systemImage) {
                        EffectMenu(selection: $settings.effectStyle)
                            .frame(maxWidth: 130)
                    } label: { Text("Effect").fixedSize() }
                    Divider().padding(.leading, 38)
                    toggleRow("hand.tap.fill", "Vanish on finger snap",
                              isOn: Binding(get: { settings.snapEnabled }, set: { model.setSnapEnabled($0) }))
                    Divider().padding(.leading, 38)
                    toggleRow("hand.raised.fingers.spread.fill", "Vanish on “V” gesture", isOn: $settings.vSignEnabled)
                }
            }

            if let msg = model.message {
                Callout(verbatim: msg, systemImage: "xmark.octagon.fill", tint: .red)
            }

            footer
        }
        .padding(14)
        .frame(width: 320)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            AppIconView(size: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: Brand.name).font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(statusDetail).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            StatusPill(text: statusShort, color: statusColor, pulsing: isLive)
        }
    }

    // MARK: Main action

    private var heroButton: some View {
        Button {
            model.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: model.status.targetHidden ? "person.fill.viewfinder" : "sparkles")
                Text(model.status.targetHidden ? "Appear" : "Vanish")
                Spacer()
                KeyCap(text: settings.shortcut.display, onDark: true)
            }
        }
        .buttonStyle(HeroButtonStyle(hidden: model.status.targetHidden))
        .disabled(!model.status.hasPlate && !model.status.targetHidden)
        .help(Text("Shortcut: \(settings.shortcut.display)"))
    }

    @ViewBuilder private var notices: some View {
        if !model.status.hasPlate {
            Button { open(.studio) } label: {
                Callout(text: "Capture the empty room to enable vanishing.", systemImage: "camera.viewfinder")
            }
            .buttonStyle(.plain)
        } else if model.status.plateCameraMismatch {
            Button { open(.studio) } label: {
                Callout(text: "Room snapshot was taken with another camera.")
            }
            .buttonStyle(.plain)
        }
    }

    private var installHint: some View {
        VStack(alignment: .leading, spacing: 10) {
            Callout(text: "Ghosted Camera is not installed yet.", systemImage: "video.slash.fill", tint: Brand.violet)
            Button { open(.setup) } label: {
                HStack {
                    Image(systemName: "wand.and.stars")
                    Text("Open setup guide")
                    Spacer()
                    Image(systemName: "arrow.right")
                }
            }
            .buttonStyle(HeroButtonStyle(hidden: false))
        }
    }

    // MARK: Rows

    private func row<Trailing: View, Label: View>(_ icon: String, @ViewBuilder trailing: () -> Trailing,
                                                  @ViewBuilder label: () -> Label) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Brand.vanishGradient))
            label()
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private func toggleRow(_ icon: String, _ title: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
        row(icon) {
            Toggle(title, isOn: isOn).labelsHidden().toggleStyle(.switch).controlSize(.mini)
        } label: {
            Text(title)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 2) {
            footerButton("Studio…", icon: MainTab.studio.systemImage) { open(.studio) }
            footerButton("Setup…", icon: MainTab.setup.systemImage) { open(.setup) }
            footerButton("Settings…", icon: MainTab.settings.systemImage) { open(.settings) }
            Spacer()
            footerButton("Quit", icon: "power") { NSApp.terminate(nil) }
        }
    }

    private func footerButton(_ title: LocalizedStringKey, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .frame(width: 32, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(FooterIconStyle())
        .help(Text(title))
        .accessibilityLabel(Text(title))
    }

    // MARK: Status

    private var isLive: Bool { model.devicePresent && (model.clients?.count ?? 0) > 0 }

    private var statusColor: Color {
        if !model.devicePresent { return .gray }
        if isLive { return model.status.targetHidden ? Brand.violet : .green }
        return .secondary
    }

    private var statusShort: String {
        if !model.devicePresent { return String(localized: "Not installed") }
        if isLive { return model.status.targetHidden ? String(localized: "Vanished") : String(localized: "On air") }
        return String(localized: "Idle")
    }

    private var statusDetail: String {
        if !model.devicePresent { return String(localized: "Finish setup to add the camera") }
        if let name = model.consumerName {
            return String(localized: "In use by \(name)")
        }
        if isLive { return String(localized: "In use") }
        return String(localized: "Select “Ghosted Camera” in your call app")
    }

    private func open(_ tab: MainTab) {
        OpenMainAction(openWindow: openWindow, model: model)(tab)
    }
}

private struct FooterIconStyle: ButtonStyle {
    @State private var hover = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(hover ? Color.primary : Color.secondary)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.14 : hover ? 0.08 : 0))
            )
            .onHover { hover = $0 }
    }
}
