import Foundation

/// Who is consuming the virtual camera. Encoded as "count|signingID" for a CMIO string property.
public struct ClientInfo: Equatable, Sendable {
    public var count: Int
    public var signingID: String?

    public init(count: Int, signingID: String?) {
        self.count = count
        self.signingID = signingID
    }

    public var encoded: String { "\(count)|\(signingID ?? "")" }

    public init?(encoded: String) {
        let parts = encoded.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, let c = Int(parts[0]) else { return nil }
        count = c
        signingID = parts[1].isEmpty ? nil : String(parts[1])
    }

    private static let known: [String: String] = [
        "us.zoom.xos": "Zoom",
        "com.google.Chrome": "Google Chrome",
        "com.apple.Safari": "Safari",
        "com.apple.WebKit.GPU": "Safari",
        "org.mozilla.firefox": "Firefox",
        "com.microsoft.edgemac": "Microsoft Edge",
        "com.microsoft.teams2": "Microsoft Teams",
        "com.microsoft.teams": "Microsoft Teams",
        "ru.keepcoder.Telegram": "Telegram",
        "org.telegram.desktop": "Telegram",
        "com.tdesktop.Telegram": "Telegram",
        "com.apple.FaceTime": "FaceTime",
        "com.apple.avconferenced": "FaceTime",
        "com.tinyspeck.slackmacgap": "Slack",
        "com.hnc.Discord": "Discord",
        "com.apple.PhotoBooth": "Photo Booth",
        "com.apple.QuickTimePlayerX": "QuickTime Player",
        "com.cisco.webexmeetingsapp": "Webex",
        "com.brave.Browser": "Brave",
        "company.thebrowser.Browser": "Arc",
    ]

    public static func friendlyName(for signingID: String) -> String {
        if let n = known[signingID] { return n }
        if let prefix = known.keys.first(where: { signingID.hasPrefix($0 + ".") }) { return known[prefix]! }
        return signingID
    }
}
