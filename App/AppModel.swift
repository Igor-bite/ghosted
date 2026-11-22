import AppKit
import AVFoundation
import ImageIO
import Combine
import ServiceManagement
import UserNotifications
import VanishCore

/// Coordinates settings, the extension, the pipeline and triggers. Main actor.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    enum RoomCaptureState: Equatable {
        case idle
        case countdown(Int)
        case capturing
        case done(Pipeline.RoomCaptureOutcome)
    }

    let settings = AppSettings()
    let installer = ExtensionInstaller()
    let preview = PreviewSink()
    let backgrounds = BackgroundLibrary()
    private(set) var pipeline: Pipeline?

    @Published private(set) var status = Pipeline.Status()
    @Published private(set) var clients: ClientInfo?
    @Published private(set) var devicePresent = false
    @Published private(set) var cameras: [CameraInfo] = []
    @Published private(set) var cameraAuthorized = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    @Published var previewOpen = false { didSet { updateDemand() } }
    @Published private(set) var roomCapture: RoomCaptureState = .idle
    @Published private(set) var message: String?
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published private(set) var hotKeyFailed = false
    /// Thumbnail of the captured empty room, if any.
    @Published private(set) var roomThumbnail: NSImage?

    private var hotKey: HotKey?
    private let snap = SnapDetector()
    private var pollTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []
    private var messageTask: Task<Void, Never>?

    private init() {
        pipeline = Pipeline(restoreHidden: settings.lastHidden)
        guard let pipeline else {
            message = String(localized: "Metal is not available on this Mac.")
            return
        }
        pipeline.onStatus = { [weak self] s in
            guard let self else { return }
            self.status = s
            if self.settings.lastHidden != s.targetHidden { self.settings.lastHidden = s.targetHidden }
        }
        pipeline.onNeedsRoomPlate = { [weak self] in
            self?.flash(String(localized: "Capture the empty room first."))
        }
        pipeline.onGestureTrigger = { [weak self] in self?.toggle(fromGesture: true) }
        pipeline.onFrame = { [weak self] pb in self?.preview.push(pb) }
        pipeline.capture.onDevicesChanged = { [weak self] in self?.refreshCameras() }
        pipeline.selectCamera(settings.cameraID)

        snap.onSnap = { [weak self] in self?.toggle(fromGesture: true) }
        // Snap trigger is opt-in: never touch the microphone (and never prompt) at launch
        // unless access was already granted when the user turned it on.
        if settings.snapEnabled && !Self.micAuthorized { settings.snapEnabled = false }

        settings.objectWillChange
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] in self?.applySettings() }
            .store(in: &cancellables)
        applySettings()
        refreshCameras()
        refreshRoomThumbnail()

        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        poll()
    }

    // MARK: Actions

    func toggle(fromGesture: Bool = false) {
        if !fromGesture { snap.noteTrigger() }
        pipeline?.trigger()
    }

    func selectCamera(_ id: String?) {
        settings.cameraID = id
        pipeline?.selectCamera(id)
    }

    func requestCameraAccess() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            Task { @MainActor in
                self.cameraAuthorized = granted
                self.refreshCameras()
                self.updateDemand()
            }
        }
    }

    func startRoomCapture() {
        guard roomCapture == .idle || isRoomCaptureDone else { return }
        Task {
            for n in stride(from: 5, through: 1, by: -1) {
                roomCapture = .countdown(n)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            roomCapture = .capturing
            updateDemand()
            pipeline?.captureRoom { [weak self] outcome in
                guard let self else { return }
                self.roomCapture = .done(outcome)
                self.refreshRoomThumbnail()
                self.updateDemand()
            }
        }
        updateDemand()
    }

    func resetRoomCaptureState() {
        if isRoomCaptureDone { roomCapture = .idle }
    }

    private var isRoomCaptureDone: Bool {
        if case .done = roomCapture { return true }
        return false
    }

    // MARK: Backgrounds

    /// nil = empty-room snapshot.
    func selectBackground(_ id: String?) {
        settings.backgroundID = id
    }

    /// Lets the user pick an image file, adds it to the library and selects it.
    func addBackgroundFromFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "Choose an image for the virtual background")
        bringToFront()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            selectBackground(try backgrounds.add(from: url))
        } catch {
            flash(String(localized: "This file can’t be used as a background."))
        }
    }

    func removeBackground(_ id: String) {
        if settings.backgroundID == id { selectBackground(nil) }
        backgrounds.remove(id: id)
    }

    var backgroundName: String {
        backgrounds.item(id: settings.backgroundID)?.name ?? String(localized: "Room snapshot")
    }

    private func refreshRoomThumbnail() {
        guard let src = CGImageSourceCreateWithURL(RoomPlateStore.imageURL as CFURL, nil),
              let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 320,
              ] as CFDictionary)
        else { roomThumbnail = nil; return }
        roomThumbnail = NSImage(cgImage: thumb, size: NSSize(width: 160, height: 90))
    }

    private var appliedBackgroundID: String??

    private func applyBackground() {
        let id = settings.backgroundID
        guard appliedBackgroundID != .some(id) else { return }
        appliedBackgroundID = .some(id)
        guard let id else { pipeline?.setVirtualBackground(nil); return }
        guard let image = backgrounds.image(for: id) else {
            // Missing file (deleted outside the app): fall back to the room snapshot.
            settings.backgroundID = nil
            return
        }
        pipeline?.setVirtualBackground(image)
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            flash(error.localizedDescription)
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setSnapEnabled(_ on: Bool) {
        guard on else { settings.snapEnabled = false; return }
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            Task { @MainActor in
                self.settings.snapEnabled = granted
                if !granted { self.flash(String(localized: "Microphone access is needed for snap detection.")) }
            }
        }
    }

    // MARK: Internals

    private func applySettings() {
        applyBackground()
        pipeline?.setConfig(.init(dustEnabled: settings.dustEnabled,
                                  hybridRoom: settings.hybridRoom,
                                  effectDuration: settings.effectDuration,
                                  vSignEnabled: settings.vSignEnabled))
        if hotKey == nil || hotKeyShortcut != settings.shortcut {
            hotKey = nil
            hotKey = HotKey(settings.shortcut) { [weak self] in self?.toggle() }
            hotKeyShortcut = settings.shortcut
            hotKeyFailed = hotKey == nil
        }
        snap.threshold = settings.snapThreshold
        if settings.snapEnabled && Self.micAuthorized && !snap.isRunning {
            do { try snap.start() } catch { flash(error.localizedDescription) }
        } else if !settings.snapEnabled && snap.isRunning {
            snap.stop()
        }
    }
    private var hotKeyShortcut: Shortcut?

    private static var micAuthorized: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    private func poll() {
        devicePresent = VirtualCameraSink.isDevicePresent
        if devicePresent { installer.markInstalledIfUnknown() }
        let c = VirtualCameraSink.readClients()
        if c != clients { clients = c }
        cameraAuthorized = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        launchAtLogin = SMAppService.mainApp.status == .enabled
        updateDemand()
    }

    private func refreshCameras() {
        cameras = CameraCapture.cameraList()
    }

    private func updateDemand() {
        let roomBusy: Bool
        switch roomCapture {
        case .countdown, .capturing: roomBusy = true
        default: roomBusy = false
        }
        let watched = (clients?.count ?? 0) > 0
        pipeline?.setRunning(cameraAuthorized && (watched || previewOpen || roomBusy))
    }

    func flash(_ text: String) {
        message = text
        NSSound.beep()
        messageTask?.cancel()
        messageTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled { message = nil }
        }
        let content = UNMutableNotificationContent()
        content.title = Brand.name
        content.body = text
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }

    var consumerName: String? {
        guard let c = clients, c.count > 0 else { return nil }
        return c.signingID.map(ClientInfo.friendlyName(for:))
    }
}
