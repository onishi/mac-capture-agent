import Foundation

/// A parsed natural-language memory query.
public struct MemoryQuery: Sendable, Equatable {
    /// Remaining free text (keywords / semantic part).
    public var text: String
    public var dateRange: DateInterval?
    /// Base language code of the original text, e.g. "fr".
    public var language: String?

    public init(text: String, dateRange: DateInterval? = nil, language: String? = nil) {
        self.text = text
        self.dateRange = dateRange
        self.language = language
    }

    public var hasFilters: Bool { dateRange != nil || language != nil }
}

/// Understands simple time and language expressions in Japanese and English:
/// "昨日見ていたフランス語の美術館", "french museum yesterday", "さっきの英語".
public enum MemoryQueryParser {
    private static let languageNames: [(String, [String])] = [
        ("fr", ["フランス語", "french", "français"]),
        ("en", ["英語", "english"]),
        ("de", ["ドイツ語", "german", "deutsch"]),
        ("es", ["スペイン語", "spanish", "español"]),
        ("it", ["イタリア語", "italian"]),
        ("pt", ["ポルトガル語", "portuguese"]),
        ("zh", ["中国語", "chinese"]),
        ("ko", ["韓国語", "korean"]),
        ("ru", ["ロシア語", "russian"]),
        ("ja", ["日本語", "japanese"])
    ]

    private static let fillers = [
        "見ていた", "見てた", "見た", "読んでいた", "読んだ", "やつ", "もの", "とき",
        "i saw", "i read", "that i", "seen", "saw", "the ", " the", "something", "about"
    ]

    private static let particles = CharacterSet(charactersIn: "のをはがにでとへもや、。 ")

    public static func parse(_ raw: String, now: Date, calendar: Calendar = .current) -> MemoryQuery {
        var text = raw.lowercased()
        var query = MemoryQuery(text: "")

        // Order matters: "一昨日" before "昨日", "last week" before "week".
        let startOfToday = calendar.startOfDay(for: now)
        let day: TimeInterval = 24 * 60 * 60
        let dateWords: [(words: [String], range: () -> DateInterval)] = [
            (["一昨日", "おととい", "day before yesterday"], {
                let start = calendar.date(byAdding: .day, value: -2, to: startOfToday) ?? startOfToday.addingTimeInterval(-2 * day)
                return DateInterval(start: start, duration: day)
            }),
            (["昨日", "きのう", "yesterday"], {
                let start = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday.addingTimeInterval(-day)
                return DateInterval(start: start, duration: day)
            }),
            (["今日", "きょう", "today"], {
                DateInterval(start: startOfToday, end: max(now, startOfToday))
            }),
            (["さっき", "さきほど", "先ほど", "just now", "earlier", "recently"], {
                DateInterval(start: now.addingTimeInterval(-2 * 60 * 60), end: now)
            }),
            (["先週", "last week"], {
                let start = calendar.date(byAdding: .day, value: -14, to: startOfToday) ?? startOfToday
                let end = calendar.date(byAdding: .day, value: -7, to: startOfToday) ?? startOfToday
                return DateInterval(start: start, end: max(end, start))
            }),
            (["今週", "this week", "最近", "lately"], {
                let start = calendar.date(byAdding: .day, value: -7, to: startOfToday) ?? startOfToday
                return DateInterval(start: start, end: now)
            })
        ]

        for entry in dateWords {
            if let word = entry.words.first(where: { text.contains($0) }) {
                query.dateRange = entry.range()
                text = text.replacingOccurrences(of: word, with: " ")
                break
            }
        }

        for (code, names) in languageNames {
            if let name = names.first(where: { text.contains($0) }) {
                query.language = code
                text = text.replacingOccurrences(of: name, with: " ")
                break
            }
        }

        for filler in fillers {
            text = text.replacingOccurrences(of: filler, with: " ")
        }

        // Collapse, then trim dangling Japanese particles left by the removals.
        let tokens = text
            .split(whereSeparator: { $0.isWhitespace })
            .map { String($0).trimmingCharacters(in: particles) }
            .filter { !$0.isEmpty }
        query.text = tokens.joined(separator: " ")
        return query
    }
}
