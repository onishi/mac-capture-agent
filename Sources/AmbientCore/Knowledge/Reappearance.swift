import Foundation

/// "Seen before" notices: shown only when something comes back after at least
/// a day, so the same browsing session never triggers it.
public enum Reappearance {
    /// Whole calendar days between `lastSeen` and `now`, or nil when it is too recent.
    public static func daysSince(_ lastSeen: Date?, now: Date, calendar: Calendar = .current, minimumDays: Int = 1) -> Int? {
        guard let lastSeen, lastSeen < now else { return nil }
        let start = calendar.startOfDay(for: lastSeen)
        let end = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        return days >= minimumDays ? days : nil
    }

    /// Localized label, e.g. "3日前にも表示されています" / "Seen 3 days ago".
    public static func label(days: Int, language: String) -> String {
        if LanguageCode.base(language) == "ja" {
            return days == 1 ? "昨日も表示されています" : "\(days)日前にも表示されています"
        }
        return days == 1 ? "Seen yesterday" : "Seen \(days) days ago"
    }
}
