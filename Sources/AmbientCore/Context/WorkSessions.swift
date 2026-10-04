import Foundation

/// One period with a page in front.
public struct PageVisit: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let key: PageKey
    public let application: String?
    public let bundleIdentifier: String?
    public let title: String?
    public let url: URL?
    public let start: Date
    public let end: Date

    public init(id: UUID = UUID(), key: PageKey, application: String?, bundleIdentifier: String?,
                title: String?, url: URL?, start: Date, end: Date) {
        self.id = id
        self.key = key
        self.application = application
        self.bundleIdentifier = bundleIdentifier
        self.title = title
        self.url = url
        self.start = start
        self.end = max(start, end)
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }

    /// Words that describe what the visit is about (title words and host).
    public var topicTokens: Set<String> {
        var tokens = Set<String>()
        if let host = url.map(URLSanitizer.displayHost) { tokens.insert(host) }
        let words = (title ?? "")
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "#" })
            .map(String.init)
        for word in words where word.count >= 3 && !WorkSessionClusterer.stopWords.contains(word) {
            tokens.insert(word)
        }
        return tokens
    }
}

/// A run of related visits across apps ("Cinema Timetable feature development").
public struct WorkSessionDraft: Sendable, Equatable {
    public var visits: [PageVisit]

    public var id: UUID { visits.first?.id ?? UUID() }
    public var start: Date { visits.first?.start ?? .distantPast }
    public var end: Date { visits.last?.end ?? .distantPast }
    /// Time actually spent (sum of visits, not wall clock).
    public var activeDuration: TimeInterval { visits.reduce(0) { $0 + $1.duration } }

    public var applications: [String] {
        var seen: [String] = []
        for visit in visits {
            if let app = visit.application, !seen.contains(app) { seen.append(app) }
        }
        return seen
    }

    /// Most frequent topic tokens weighted by time.
    public func keywords(limit: Int = 5) -> [String] {
        var weights: [String: Double] = [:]
        for visit in visits {
            for token in visit.topicTokens {
                weights[token, default: 0] += max(1, visit.duration)
            }
        }
        return weights.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.prefix(limit).map(\.key)
    }

    /// Name without a language model: top keywords, else the main app.
    public var fallbackName: String {
        let words = keywords(limit: 3)
        if !words.isEmpty { return words.joined(separator: " · ") }
        return applications.first ?? "Session"
    }
}

/// Groups visits into work sessions: a new session starts after an idle gap,
/// or when the topic changes and stays changed for a while.
public struct WorkSessionClusterer: Sendable {
    public var idleGap: TimeInterval = 20 * 60
    /// A topic change must last this long to split the session (short detours stay in).
    public var topicChangeDuration: TimeInterval = 10 * 60

    static let stopWords: Set<String> = [
        "the", "and", "for", "with", "you", "your", "new", "tab", "page", "home", "untitled", "google", "search",
        "chrome", "safari", "firefox", "edge", "arc", "window", "inbox", "mail", "slack", "github", "com",
        "www", "http", "https", "html", "index", "main", "edit", "file", "view"
    ]

    public init() {}

    public func cluster(_ visits: [PageVisit]) -> [WorkSessionDraft] {
        let sorted = visits.sorted { $0.start < $1.start }
        var sessions: [WorkSessionDraft] = []
        var current: [PageVisit] = []
        var currentTokens = Set<String>()
        var detour: [PageVisit] = []

        func flushDetourIntoCurrent() {
            current += detour
            detour = []
        }

        for visit in sorted {
            if let last = (detour.last ?? current.last), visit.start.timeIntervalSince(last.end) > idleGap {
                flushDetourIntoCurrent()
                if !current.isEmpty { sessions.append(WorkSessionDraft(visits: current)) }
                current = [visit]
                currentTokens = visit.topicTokens
                continue
            }
            if current.isEmpty {
                current = [visit]
                currentTokens = visit.topicTokens
                continue
            }
            let tokens = visit.topicTokens
            let related = tokens.isEmpty || currentTokens.isEmpty || !tokens.isDisjoint(with: currentTokens)
                || visit.bundleIdentifier.map(AppContextClassifier.codingBundleIdentifiers.contains) == true
            if related {
                flushDetourIntoCurrent()
                current.append(visit)
                currentTokens.formUnion(tokens)
            } else {
                detour.append(visit)
                let detourDuration = detour.reduce(0) { $0 + $1.duration }
                if detourDuration >= topicChangeDuration {
                    sessions.append(WorkSessionDraft(visits: current))
                    current = detour
                    currentTokens = detour.reduce(into: Set<String>()) { $0.formUnion($1.topicTokens) }
                    detour = []
                }
            }
        }
        flushDetourIntoCurrent()
        if !current.isEmpty { sessions.append(WorkSessionDraft(visits: current)) }
        return sessions
    }
}

/// "Today's main themes" with minutes, from named sessions.
public enum DailySummary {
    public struct Theme: Sendable, Equatable {
        public let name: String
        public let minutes: Int
    }

    public static func themes(_ sessions: [(name: String, activeDuration: TimeInterval)], minimumMinutes: Int = 3) -> [Theme] {
        var minutes: [String: Double] = [:]
        for session in sessions {
            minutes[session.name, default: 0] += session.activeDuration / 60
        }
        return minutes
            .map { Theme(name: $0.key, minutes: Int($0.value.rounded())) }
            .filter { $0.minutes >= minimumMinutes }
            .sorted { $0.minutes == $1.minutes ? $0.name < $1.name : $0.minutes > $1.minutes }
    }
}

/// When to offer "pick up where you left off".
public enum ResumePolicy {
    /// Offer the last session when it ended at least `minimumGap` ago and within `maximumAge`.
    public static func shouldOffer(lastSessionEnd: Date?, now: Date, minimumGap: TimeInterval = 4 * 60 * 60,
                                   maximumAge: TimeInterval = 3 * 24 * 60 * 60, alreadyOfferedToday: Bool) -> Bool {
        guard !alreadyOfferedToday, let end = lastSessionEnd else { return false }
        let age = now.timeIntervalSince(end)
        return age >= minimumGap && age <= maximumAge
    }
}

/// QR code payloads: URLs are shown as their host + path, other text as-is (truncated).
public enum QRContent {
    public static func display(_ payload: String) -> (isURL: Bool, text: String)? {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URLSanitizer.sanitize(trimmed) {
            let path = url.path == "/" ? "" : url.path
            return (true, URLSanitizer.displayHost(url) + path)
        }
        return (false, String(trimmed.prefix(80)))
    }
}
