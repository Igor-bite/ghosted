import Foundation
import os.log
import SystemExtensions

private let log = Logger(subsystem: "com.vanishcam.Vanish", category: "installer")

/// Installs / replaces / removes the Vanish Camera system extension.
@MainActor
final class ExtensionInstaller: NSObject, ObservableObject {
    enum State: Equatable {
        case unknown
        case installing
        case needsApproval
        case installed
        case removing
        case removed
        case failed(String)
    }

    @Published private(set) var state: State = .unknown

    var isInAppsFolder: Bool {
        Bundle.main.bundleURL.path.hasPrefix("/Applications/")
    }

    func activate() {
        state = .installing
        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: VanishConstants.extensionBundleID, queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    func deactivate() {
        state = .removing
        let request = OSSystemExtensionRequest.deactivationRequest(
            forExtensionWithIdentifier: VanishConstants.extensionBundleID, queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    /// Called by the pipeline when the virtual device is visible: it must be installed.
    func markInstalledIfUnknown() {
        if state == .unknown || state == .needsApproval || state == .installing { state = .installed }
    }

    fileprivate var pendingRemoval = false
}

extension ExtensionInstaller: OSSystemExtensionRequestDelegate {
    nonisolated func request(_ request: OSSystemExtensionRequest,
                             actionForReplacingExtension existing: OSSystemExtensionProperties,
                             withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        log.info("Replacing extension \(existing.bundleShortVersion, privacy: .public) (\(existing.bundleVersion, privacy: .public)) with \(ext.bundleShortVersion, privacy: .public) (\(ext.bundleVersion, privacy: .public))")
        return .replace
    }

    nonisolated func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        Task { @MainActor in self.state = .needsApproval }
    }

    nonisolated func request(_ request: OSSystemExtensionRequest,
                             didFinishWithResult result: OSSystemExtensionRequest.Result) {
        Task { @MainActor in
            if self.state == .removing {
                self.state = .removed
            } else {
                self.state = result == .willCompleteAfterReboot ? .needsApproval : .installed
            }
        }
    }

    nonisolated func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        log.error("Extension request failed: \(error.localizedDescription, privacy: .public)")
        let nsError = error as NSError
        Task { @MainActor in
            if nsError.domain == OSSystemExtensionErrorDomain,
               nsError.code == OSSystemExtensionError.Code.extensionNotFound.rawValue,
               self.state == .removing {
                self.state = .removed
                return
            }
            self.state = .failed(error.localizedDescription)
        }
    }
}
