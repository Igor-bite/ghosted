import CoreMedia
import CoreVideo
import Foundation

/// Values shared by the app and the camera extension.
enum VanishConstants {
    static let deviceName = "Vanish Camera"
    static let deviceModel = "Vanish Virtual Camera"
    static let manufacturer = "Vanish"
    static let sourceStreamName = "Vanish Camera Video"
    static let sinkStreamName = "Vanish Camera Input"

    /// Stable IDs so apps remember the selected camera across reinstalls.
    static let deviceID = UUID(uuidString: "5A1F0C3E-7B2D-4E8A-9C61-2B7D3E4F5A60")!
    static let sourceStreamID = UUID(uuidString: "5A1F0C3E-7B2D-4E8A-9C61-2B7D3E4F5A61")!
    static let sinkStreamID = UUID(uuidString: "5A1F0C3E-7B2D-4E8A-9C61-2B7D3E4F5A62")!

    static let width: Int32 = 1280
    static let height: Int32 = 720
    static let fps: Int32 = 30
    static let pixelFormat: OSType = kCVPixelFormatType_32BGRA

    /// Seconds without sink frames before the extension shows the stub.
    static let staleTimeout: TimeInterval = 0.5

    /// Custom device property "vcli": ClientInfo encoded as "count|signingID".
    static let clientsPropertyFourCC = "vcli"
    static var clientsPropertySelector: UInt32 {
        clientsPropertyFourCC.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    static let extensionBundleID = "com.vanishcam.Vanish.CameraExtension"
}
