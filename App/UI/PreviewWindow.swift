import SwiftUI

struct PreviewWindow: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                PreviewLayerView(sink: model.preview)
                overlay
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .frame(minWidth: 640)

            HStack(spacing: 12) {
                Button {
                    model.resetRoomCaptureState()
                    model.startRoomCapture()
                } label: {
                    Label("Capture empty room", systemImage: "camera.viewfinder")
                }
                .disabled(isCapturing || !model.cameraAuthorized)

                Button {
                    model.toggle()
                } label: {
                    Label(model.status.targetHidden ? "Appear" : "Vanish",
                          systemImage: model.status.targetHidden ? "person.fill" : "sparkles")
                }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(!model.status.hasPlate && !model.status.targetHidden)

                Spacer()
                Text("Don’t move the camera or change the lighting after capturing the room.")
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(12)
        }
        .onAppear { model.previewOpen = true }
        .onDisappear { model.previewOpen = false }
    }

    private var isCapturing: Bool {
        switch model.roomCapture {
        case .countdown, .capturing: return true
        default: return false
        }
    }

    @ViewBuilder private var overlay: some View {
        if !model.cameraAuthorized {
            VStack(spacing: 10) {
                Text("Vanish needs access to your camera.").foregroundStyle(.white)
                Button("Allow camera access") { model.requestCameraAccess() }
            }
        } else {
            switch model.roomCapture {
            case .countdown(let n):
                VStack {
                    Text("Step out of the frame").font(.title2).foregroundStyle(.white)
                    Text("\(n)").font(.system(size: 96, weight: .bold, design: .rounded)).foregroundStyle(.white)
                }
                .shadow(radius: 8)
            case .capturing:
                ProgressView().controlSize(.large)
            case .done(let outcome):
                resultBanner(outcome)
            case .idle:
                EmptyView()
            }
        }
    }

    private func resultBanner(_ outcome: Pipeline.RoomCaptureOutcome) -> some View {
        let (text, color): (LocalizedStringKey, Color) = {
            switch outcome {
            case .ok: return ("Room captured. You can vanish now.", .green)
            case .personDetected: return ("Someone is still in the frame. Retake the snapshot for a clean result.", .orange)
            case .failed: return ("Could not capture the room. Try again.", .red)
            }
        }()
        return VStack {
            Spacer()
            Text(text)
                .padding(10)
                .background(color.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(.white)
                .padding(.bottom, 16)
                .onTapGesture { model.resetRoomCaptureState() }
        }
    }
}
