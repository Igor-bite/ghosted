import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var installer: ExtensionInstaller
    @State private var recording = false
    @State private var monitor: Any?
    @State private var shortcutError: String?
    @State private var confirmRemove = false

    var body: some View {
        Form {
            Section("Trigger") {
                HStack {
                    Text("Shortcut")
                    Spacer()
                    Button(recording ? String(localized: "Press keys…") : settings.shortcut.display) {
                        recording ? stopRecording() : startRecording()
                    }
                    .monospaced()
                    Button("Reset") { settings.shortcut = .default }
                }
                if let shortcutError { Text(shortcutError).font(.caption).foregroundStyle(.red) }
                if model.hotKeyFailed {
                    Text("This shortcut is taken by another app. Choose a different one.")
                        .font(.caption).foregroundStyle(.red)
                }
                Toggle("Vanish on finger snap", isOn: Binding(get: { settings.snapEnabled },
                                                               set: { model.setSnapEnabled($0) }))
                if settings.snapEnabled {
                    HStack {
                        Text("Snap sensitivity")
                        Slider(value: Binding(get: { 1.6 - settings.snapThreshold },
                                              set: { settings.snapThreshold = 1.6 - $0 }),
                               in: 0.65...0.95)
                    }
                }
                Toggle("Vanish on “V” gesture (hold 0.5 s)", isOn: $settings.vSignEnabled)
            }

            Section("Effect") {
                Toggle("Dust effect", isOn: $settings.dustEnabled)
                HStack {
                    Text("Duration")
                    Slider(value: $settings.effectDuration, in: 1...3, step: 0.1)
                    Text(String(format: "%.1f s", settings.effectDuration)).monospacedDigit().frame(width: 44)
                }
                .disabled(!settings.dustEnabled)
                Picker("Room while vanished", selection: $settings.hybridRoom) {
                    Text("Live room (recommended)").tag(true)
                    Text("Static snapshot").tag(false)
                }
                Text("Live room keeps lights and windows moving. Use Static if edges of your silhouette remain visible.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("General") {
                Toggle("Open Vanish at login", isOn: Binding(get: { model.launchAtLogin },
                                                              set: { model.setLaunchAtLogin($0) }))
                Button("Remove Vanish Camera from this Mac…", role: .destructive) { confirmRemove = true }
                Text("Do this before deleting the app.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .confirmationDialog("Remove Vanish Camera?", isPresented: $confirmRemove) {
            Button("Remove", role: .destructive) { installer.deactivate() }
        } message: {
            Text("Call apps will no longer see Vanish Camera. You can reinstall it from the setup guide.")
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        shortcutError = nil
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stopRecording(); return nil } // Esc
            guard let s = Shortcut(event: event) else { return nil }
            if s.isAllowed {
                settings.shortcut = s
            } else {
                shortcutError = String(localized: "Use ⌃ or ⌘ in the shortcut — macOS blocks ⌥-only global shortcuts.")
            }
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
