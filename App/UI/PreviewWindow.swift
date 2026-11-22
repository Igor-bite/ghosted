import SwiftUI

struct PreviewWindow: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                PreviewLayerView(sink: model.preview)
                overlay
                VStack {
                    HStack {
                        roomChip
                        Spacer()
                        if model.status.targetHidden {
                            hudChip(Text("Vanished"), systemImage: "sparkles", tint: Brand.violet)
                        }
                    }
                    Spacer()
                }
                .padding(12)
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .frame(minWidth: 640)
            .background(Color.black)

            toolbar
        }
        .tint(Brand.violet)
        .onAppear { model.previewOpen = true }
        .onDisappear { model.previewOpen = false }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button {
                model.resetRoomCaptureState()
                model.startRoomCapture()
            } label: {
                Label(model.status.hasPlate ? "Retake empty room" : "Capture empty room",
                      systemImage: "camera.viewfinder")
                    .padding(.horizontal, 4)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(isCapturing || !model.cameraAuthorized)

            Button {
                model.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: model.status.targetHidden ? "person.fill.viewfinder" : "sparkles")
                    Text(model.status.targetHidden ? "Appear" : "Vanish")
                    KeyCap(text: String(localized: "Space"), onDark: true)
                }
            }
            .buttonStyle(HeroButtonStyle(hidden: model.status.targetHidden))
            .frame(width: 190)
            .keyboardShortcut(.space, modifiers: [])
            .disabled(!model.status.hasPlate && !model.status.targetHidden)

            Spacer()

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "info.circle")
                Text("Don’t move the camera or change the lighting after capturing the room.")
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: 260, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.bar)
    }

    // MARK: Overlays

    private var isCapturing: Bool {
        switch model.roomCapture {
        case .countdown, .capturing: return true
        default: return false
        }
    }

    private var roomChip: some View {
        Group {
            if model.status.usingVirtualBackground {
                hudChip(Text(model.backgroundName), systemImage: "photo.fill", tint: Brand.cyan)
            } else if !model.status.hasPlate {
                hudChip(Text("No room snapshot"), systemImage: "camera.viewfinder", tint: .orange)
            } else if model.status.plateCameraMismatch {
                hudChip(Text("Room taken with another camera"), systemImage: "exclamationmark.triangle.fill", tint: .orange)
            } else {
                hudChip(Text("Room ready"), systemImage: "checkmark.circle.fill", tint: .green)
            }
        }
    }

    private func hudChip(_ text: Text, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage).foregroundStyle(tint)
            text.foregroundStyle(.white)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder private var overlay: some View {
        if !model.cameraAuthorized {
            VStack(spacing: 14) {
                Image(systemName: "video.slash.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(Brand.vanishGradient)
                Text("Ghosted needs access to your camera.")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Button("Allow camera access") { model.requestCameraAccess() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            .padding(28)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .environment(\.colorScheme, .dark)
        } else {
            switch model.roomCapture {
            case .countdown(let n):
                ZStack {
                    Color.black.opacity(0.35)
                    VStack(spacing: 14) {
                        ZStack {
                            Circle().stroke(.white.opacity(0.2), lineWidth: 6)
                            Circle()
                                .trim(from: 0, to: CGFloat(n) / 5)
                                .stroke(Brand.appearGradient, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .animation(.easeInOut(duration: 0.4), value: n)
                            Text("\(n)")
                                .font(.system(size: 64, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                        }
                        .frame(width: 130, height: 130)
                        Text("Step out of the frame")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                }
            case .capturing:
                VStack(spacing: 10) {
                    ProgressView().controlSize(.large)
                    Text("Capturing the room…").foregroundStyle(.white)
                }
                .padding(22)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .environment(\.colorScheme, .dark)
            case .done(let outcome):
                resultBanner(outcome)
            case .idle:
                EmptyView()
            }
        }
    }

    private func resultBanner(_ outcome: Pipeline.RoomCaptureOutcome) -> some View {
        let (text, icon, color): (LocalizedStringKey, String, Color) = {
            switch outcome {
            case .ok: return ("Room captured. You can vanish now.", "checkmark.circle.fill", .green)
            case .personDetected: return ("Someone is still in the frame. Retake the snapshot for a clean result.",
                                          "person.fill.questionmark", .orange)
            case .failed: return ("Could not capture the room. Try again.", "xmark.octagon.fill", .red)
            }
        }()
        return VStack {
            Spacer()
            HStack(spacing: 10) {
                Image(systemName: icon).foregroundStyle(color).font(.title3)
                Text(text).foregroundStyle(.white)
                Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(0.5), lineWidth: 1))
            .environment(\.colorScheme, .dark)
            .padding(.bottom, 18)
            .onTapGesture { model.resetRoomCaptureState() }
        }
    }
}
