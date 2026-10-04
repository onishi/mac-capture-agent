import Foundation

public struct CastMember: Codable, Sendable, Equatable {
    public var character: String
    public var performer: String

    public init(character: String, performer: String) {
        self.character = character
        self.performer = performer
    }
}

/// What Gemini knows about the work being watched.
public struct MediaInfoAnswer: Codable, Sendable, Equatable {
    public var isKnownWork: Bool
    public var title: String
    public var kind: String          // "movie" | "anime" | "series" | "video"
    public var year: String
    public var originalWork: String  // e.g. manga / novel it is based on; may be empty
    public var cast: [CastMember]    // up to 6 main characters with actor / voice actor
    public var music: [String]       // theme songs / notable music
    public var synopsis: String      // spoiler-safe per the requested level
    public var confidence: Double

    public static var schema: [String: Any] {
        [
            "type": "OBJECT",
            "properties": [
                "isKnownWork": ["type": "BOOLEAN"],
                "title": ["type": "STRING"],
                "kind": ["type": "STRING", "enum": ["movie", "anime", "series", "video"]],
                "year": ["type": "STRING"],
                "originalWork": ["type": "STRING"],
                "cast": ["type": "ARRAY", "items": [
                    "type": "OBJECT",
                    "properties": ["character": ["type": "STRING"], "performer": ["type": "STRING"]],
                    "required": ["character", "performer"]
                ]],
                "music": ["type": "ARRAY", "items": ["type": "STRING"]],
                "synopsis": ["type": "STRING"],
                "confidence": ["type": "NUMBER"]
            ],
            "required": ["isKnownWork", "title", "kind", "year", "originalWork", "cast", "music", "synopsis", "confidence"]
        ]
    }

    public static func instructions(spoiler: SpoilerLevel, episode: Int?, targetLanguage: String) -> String {
        """
        The user started watching something; you get its window title. If it is a published film, TV series or \
        anime you know well, fill in the fields; for ordinary online videos (vlogs, news clips, tutorials) or when \
        unsure, set isKnownWork to false. cast: up to 6 main characters with the actor or voice actor. \
        music: up to 2 theme songs. synopsis: at most 2 sentences. \(spoiler.instruction(episode: episode)) \
        Answer in the language with code "\(targetLanguage)" (keep proper names as commonly written).
        """
    }
}

/// Finds cast members whose character or performer name appears in on-screen text.
public enum CastMatcher {
    public static func matches(_ cast: [CastMember], in text: String) -> [CastMember] {
        let haystack = EntityName.canonical(text)
        return cast.filter { member in
            [member.character, member.performer].contains { name in
                let needle = EntityName.canonical(name)
                guard needle.count >= 3 || (needle.count >= 2 && needle.unicodeScalars.contains(where: TextHeuristics.isCJK)) else { return false }
                return haystack.contains(needle)
            }
        }
    }
}

// MARK: - News

public enum NewsDetector {
    public static let newsHosts: Set<String> = [
        "nhk.or.jp", "www3.nhk.or.jp", "news.yahoo.co.jp", "asahi.com", "mainichi.jp", "yomiuri.co.jp", "nikkei.com",
        "sankei.com", "jiji.com", "kyodonews.jp", "nytimes.com", "washingtonpost.com", "bbc.com", "bbc.co.uk",
        "reuters.com", "apnews.com", "theguardian.com", "cnn.com", "bloomberg.com", "ft.com", "wsj.com",
        "lemonde.fr", "spiegel.de", "elpais.com", "news.google.com"
    ]

    /// Article pages on news sites (not front pages).
    public static func isNewsArticle(_ url: URL?) -> Bool {
        guard let url else { return false }
        let host = URLSanitizer.displayHost(url)
        guard newsHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) else { return false }
        let segments = url.path.split(separator: "/").filter { !$0.isEmpty }
        return segments.count >= 2 || url.path.count > 20
    }

    /// The headline: window title without the site name ("… - NHKニュース", "… | Reuters").
    public static func headline(from windowTitle: String?) -> String? {
        guard let title = windowTitle?.trimmingCharacters(in: .whitespaces), !title.isEmpty else { return nil }
        let separators = [" | ", " - ", " – ", " — ", "｜", "：", " : "]
        var best = title
        for separator in separators {
            let parts = best.components(separatedBy: separator)
            if parts.count > 1, let longest = parts.max(by: { $0.count < $1.count }) {
                best = longest
            }
        }
        let trimmed = best.trimmingCharacters(in: .whitespaces)
        return trimmed.count >= 8 ? trimmed : nil
    }
}

public struct NewsEvent: Codable, Sendable, Equatable {
    public var date: String
    public var event: String
}

/// Background for a news story (Gemini with Google Search grounding).
public struct NewsContextAnswer: Codable, Sendable, Equatable {
    public var isNewsStory: Bool
    public var background: String
    public var timeline: [NewsEvent]
    public var relatedPeople: [String]

    public static func instructions(targetLanguage: String) -> String {
        """
        The user is reading a news article with the headline below. Using current search results, explain the \
        background briefly. Return ONLY a JSON object with these keys: "isNewsStory" (boolean), "background" \
        (one or two sentences), "timeline" (up to 3 objects {"date": "YYYY-MM or YYYY-MM-DD", "event": short text}, \
        oldest first, starting with how it began), "relatedPeople" (up to 5 names). If it is not a news story, \
        set isNewsStory to false. Answer in the language with code "\(targetLanguage)".
        """
    }
}

/// Media and news research in the cloud (Gemini in the app).
public protocol MediaResearching: Sendable {
    var isAvailable: Bool { get }
    func mediaInfo(for reference: MediaReference, spoiler: SpoilerLevel, targetLanguage: String) async throws -> MediaInfoAnswer
    func newsContext(headline: String, targetLanguage: String) async throws -> NewsContextAnswer
}

public enum MediaPolicy {
    public static let minimumConfidence = 0.7

    public static func accept(_ answer: MediaInfoAnswer) -> Bool {
        answer.isKnownWork && answer.confidence >= minimumConfidence && !answer.title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Cache identity: the same work at the same spoiler level and episode.
    public static func cacheName(for reference: MediaReference, spoiler: SpoilerLevel) -> String {
        "\(reference.title)#s\(spoiler.rawValue)e\(reference.episode ?? 0)"
    }

    /// Search words for local "related reading" (headline tokens without stop words).
    public static func keywords(fromHeadline headline: String, limit: Int = 3) -> [String] {
        let visit = PageVisit(key: PageKey(rawValue: headline), application: nil, bundleIdentifier: nil,
                              title: headline, url: nil, start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 0))
        return Array(visit.topicTokens.sorted { $0.count > $1.count }.prefix(limit))
    }
}
