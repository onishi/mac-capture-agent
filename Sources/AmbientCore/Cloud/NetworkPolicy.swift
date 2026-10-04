import Foundation

/// Every network request the app makes goes through this policy (enforced by
/// `NetworkGate` in the app). Nothing is sent until the user opts in.
public struct NetworkPolicy: Sendable, Equatable {
    public var cloudEnabled: Bool
    public var hasAPIKey: Bool
    public var performanceMode: PerformanceMode
    public var allowedHosts: Set<String>

    public static let geminiHost = "generativelanguage.googleapis.com"

    public init(cloudEnabled: Bool, hasAPIKey: Bool, performanceMode: PerformanceMode,
                allowedHosts: Set<String> = [NetworkPolicy.geminiHost]) {
        self.cloudEnabled = cloudEnabled
        self.hasAPIKey = hasAPIKey
        self.performanceMode = performanceMode
        self.allowedHosts = allowedHosts
    }

    public enum Denial: String, Sendable, Equatable {
        case notOptedIn
        case noAPIKey
        case batteryMode
        case hostNotAllowed
        case insecure
    }

    /// Whether cloud features can run at all (opt-in, key, not Battery mode).
    public var isUsable: Bool {
        cloudEnabled && hasAPIKey && performanceMode != .battery
    }

    /// Why a request to `url` would be refused, or nil when it may be sent.
    public func denial(for url: URL) -> Denial? {
        guard cloudEnabled else { return .notOptedIn }
        guard hasAPIKey else { return .noAPIKey }
        guard performanceMode != .battery else { return .batteryMode }
        guard url.scheme?.lowercased() == "https" else { return .insecure }
        guard let host = url.host?.lowercased(), allowedHosts.contains(host) else { return .hostNotAllowed }
        return nil
    }
}

/// What was sent (for the transparency list in Settings). Never the content.
public struct SentRecord: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let date: Date
    public let purpose: String
    public let host: String
    public let bytes: Int
    public let includesImage: Bool

    public init(id: UUID = UUID(), date: Date, purpose: String, host: String, bytes: Int, includesImage: Bool) {
        self.id = id
        self.date = date
        self.purpose = purpose
        self.host = host
        self.bytes = bytes
        self.includesImage = includesImage
    }
}
