import Foundation

public enum MediaSite: String, Sendable, Equatable, CaseIterable {
    case youtube, netflix, primeVideo, disneyPlus, crunchyroll, hulu, uNext, abema, dAnime, appleTV, other

    /// Title suffixes / hosts that identify the site.
    var markers: (suffixes: [String], hosts: [String]) {
        switch self {
        case .youtube: return ([" - YouTube"], ["youtube.com", "youtu.be"])
        case .netflix: return ([" | Netflix", " - Netflix", "Netflix"], ["netflix.com"])
        case .primeVideo: return ([" | Prime Video", "Prime Video: ", "Amazon.co.jp: "], ["primevideo.com"])
        case .disneyPlus: return ([" | Disney+", " | ディズニープラス"], ["disneyplus.com"])
        case .crunchyroll: return ([" - Crunchyroll", " - Watch on Crunchyroll"], ["crunchyroll.com"])
        case .hulu: return ([" | Hulu", " | Huluで"], ["hulu.com", "hulu.jp"])
        case .uNext: return ([" | U-NEXT", "| 動画配信サービス U-NEXT"], ["video.unext.jp", "unext.jp"])
        case .abema: return ([" | ABEMA", " | 新しい未来のテレビ ABEMA"], ["abema.tv"])
        case .dAnime: return ([" | dアニメストア"], ["animestore.docomo.ne.jp"])
        case .appleTV: return ([" - Apple TV"], ["tv.apple.com"])
        case .other: return ([], [])
        }
    }

    /// Sites that mostly carry anime.
    public var isAnimeSite: Bool { self == .crunchyroll || self == .dAnime }
}

/// A film / series / video identified from a window title.
public struct MediaReference: Sendable, Equatable {
    public let site: MediaSite
    public let title: String
    public let episode: Int?
    public let season: Int?

    /// Identity for "new work started" (ignores the episode).
    public var workKey: String { "\(site.rawValue)|\(EntityName.canonical(title))" }
}

/// Extracts the work title and episode from streaming-site window titles,
/// e.g. "葬送のフリーレン 第5話 | dアニメストア", "(3) Inception Trailer - YouTube",
/// "Frieren - S1E5 - Crunchyroll".
public enum MediaTitleParser {
    public static let mediaApps: Set<String> = ["com.apple.TV", "com.apple.QuickTimePlayerX", "org.videolan.vlc", "com.netflix.Netflix", "io.iina"]

    public static func parse(windowTitle: String?, url: URL?, bundleIdentifier: String?) -> MediaReference? {
        guard var title = windowTitle?.trimmingCharacters(in: .whitespaces), !title.isEmpty else { return nil }
        let host = url.map(URLSanitizer.displayHost)

        var site: MediaSite?
        for candidate in MediaSite.allCases where candidate != .other {
            if let host, candidate.markers.hosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
                site = candidate
            }
            for suffix in candidate.markers.suffixes where title.contains(suffix) {
                site = site ?? candidate
                title = title.replacingOccurrences(of: suffix, with: "")
            }
        }
        if site == nil, let bundleIdentifier, mediaApps.contains(bundleIdentifier) {
            site = bundleIdentifier == "com.netflix.Netflix" ? .netflix : (bundleIdentifier == "com.apple.TV" ? .appleTV : .other)
        }
        guard let site else { return nil }

        // "(3) Title" — YouTube notification counter.
        title = title.replacingOccurrences(of: #"^\(\d+\)\s*"#, with: "", options: .regularExpression)
        let (episode, season, cleaned) = extractEpisode(from: title)
        let finalTitle = cleaned
            .trimmingCharacters(in: CharacterSet(charactersIn: " -|:｜・—–"))
            .trimmingCharacters(in: .whitespaces)
        guard finalTitle.count >= 2, !["youtube", "netflix", "home", "ホーム"].contains(finalTitle.lowercased()) else { return nil }
        return MediaReference(site: site, title: finalTitle, episode: episode, season: season)
    }

    static func extractEpisode(from title: String) -> (episode: Int?, season: Int?, cleaned: String) {
        let patterns: [(String, Bool)] = [
            (#"S(\d{1,2})\s*E(\d{1,3})"#, true),           // S2E5
            (#"第\s*(\d{1,3})\s*[話回]"#, false),            // 第5話
            (#"(?i)\bEpisode\s*(\d{1,3})\b"#, false),
            (#"(?i)\bEp\.?\s*(\d{1,3})\b"#, false),
            (#"#(\d{1,3})\b"#, false)
        ]
        for (pattern, hasSeason) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
                  let whole = Range(match.range, in: title) else { continue }
            var season: Int?
            var episode: Int?
            if hasSeason {
                season = Range(match.range(at: 1), in: title).flatMap { Int(title[$0]) }
                episode = Range(match.range(at: 2), in: title).flatMap { Int(title[$0]) }
            } else {
                episode = Range(match.range(at: 1), in: title).flatMap { Int(title[$0]) }
            }
            var cleaned = title
            cleaned.removeSubrange(whole)
            if season == nil, let seasonMatch = cleaned.range(of: #"(?i)\bSeason\s*(\d{1,2})\b|第\s*(\d{1,2})\s*期"#, options: .regularExpression) {
                season = Int(cleaned[seasonMatch].filter(\.isNumber))
                cleaned.removeSubrange(seasonMatch)
            }
            return (episode, season, TextHeuristics.normalized(cleaned))
        }
        return (nil, nil, title)
    }
}

/// Spec §8.1: how much may be revealed about a work.
public enum SpoilerLevel: Int, Sendable, CaseIterable, Identifiable {
    case none = 0          // 完全禁止
    case uptoCurrent = 1   // 現在地点以前のみ
    case light = 2         // 軽度
    case unrestricted = 3  // 制限なし

    public var id: Int { rawValue }

    public var displayName: String {
        switch self {
        case .none: return "0 — No spoilers"
        case .uptoCurrent: return "1 — Up to where I am"
        case .light: return "2 — Light"
        case .unrestricted: return "3 — Unrestricted"
        }
    }

    /// Instruction for the model. Without a known episode, level 1 falls back to level 0.
    public func instruction(episode: Int?) -> String {
        switch self {
        case .none:
            return "STRICTLY NO SPOILERS: describe only the premise and setting known before the story starts. Never mention plot developments, deaths, twists or endings."
        case .uptoCurrent:
            if let episode {
                return "NO SPOILERS beyond episode \(episode): mention only what is revealed up to and including episode \(episode). Never mention later developments or endings."
            }
            return SpoilerLevel.none.instruction(episode: nil)
        case .light:
            return "LIGHT SPOILERS ONLY: you may mention early developments, but never major twists, deaths or endings."
        case .unrestricted:
            return "Spoilers are allowed."
        }
    }
}
