import Foundation

/// Makes browser URLs safe to store: http(s) only; query strings, fragments
/// and credentials are dropped because they often carry tokens or personal data.
public enum URLSanitizer {
    public static func sanitize(_ raw: String) -> URL? {
        guard var components = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty
        else { return nil }
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil
        components.scheme = scheme
        components.host = host.lowercased()
        return components.url
    }

    /// "github.com" (without "www.").
    public static func displayHost(_ url: URL) -> String {
        guard let host = url.host else { return url.absoluteString }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
