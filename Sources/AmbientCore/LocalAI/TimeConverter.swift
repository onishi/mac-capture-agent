import Foundation

/// Times and dates in text, read for the user's time zone (LOCAL_AI.md
/// LA-16〜LA-18): "3pm PT" → local time, Unix timestamps and ISO 8601 →
/// local date and time, and dates → "in 13 days (Tue)". Rules only; shown
/// only where the pointer rests or the user circles (like unit conversion).
public struct TimeConverter: Sendable {
    public let now: Date
    public let timeZone: TimeZone
    public let language: String

    public init(now: Date = Date(), timeZone: TimeZone = .current, targetLanguage: String) {
        self.now = now
        self.timeZone = timeZone
        self.language = LanguageCode.base(targetLanguage) == "ja" ? "ja" : "en"
    }

    private var japanese: Bool { language == "ja" }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// Conversions in reading order, at most `limit`.
    public func conversions(in text: String, limit: Int = 3) -> [UnitConversion] {
        var found: [(range: Range<String.Index>, conversion: UnitConversion)] = []
        func add(_ range: Range<String.Index>, _ conversion: UnitConversion?) {
            guard let conversion, !found.contains(where: { $0.range.overlaps(range) }) else { return }
            found.append((range, conversion))
        }
        for match in Self.isoPattern.matchesWithRanges(in: text) { add(match.range, iso(match.groups, original: text[match.range])) }
        for match in Self.unixPattern.matchesWithRanges(in: text) { add(match.range, unix(match.groups)) }
        for match in Self.zonedTimePattern.matchesWithRanges(in: text) { add(match.range, zonedTime(match.groups, original: text[match.range])) }
        for match in Self.numericDatePattern.matchesWithRanges(in: text) {
            add(match.range, date(year: int(match.groups, 1), month: int(match.groups, 2), day: int(match.groups, 3), original: text[match.range]))
        }
        for match in Self.japaneseDatePattern.matchesWithRanges(in: text) {
            add(match.range, date(year: int(match.groups, 1), month: int(match.groups, 2), day: int(match.groups, 3), original: text[match.range]))
        }
        for match in Self.englishDatePattern.matchesWithRanges(in: text) {
            let month = match.groups.count > 1 ? match.groups[1].flatMap(Self.monthNumber) : nil
            add(match.range, date(year: int(match.groups, 3), month: month, day: int(match.groups, 2), original: text[match.range]))
        }
        return found
            .sorted { $0.range.lowerBound < $1.range.lowerBound }
            .prefix(limit)
            .map { $0.conversion }
    }

    // MARK: Patterns

    private static let isoPattern = CompiledPattern(
        #"(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?(Z|[+-]\d{2}:?\d{2})"#)
    /// Seconds (2001–2039) or milliseconds since 1970, as a standalone number.
    private static let unixPattern = CompiledPattern(#"(?<![\w.,:-])(1\d{9}|2[0-1]\d{8})(\d{3})?(?![\w.,:])"#)
    private static let zoneNames = zoneOffsets.keys.sorted { $0.count > $1.count }.joined(separator: "|")
    /// "3pm PT", "3:30 p.m. ET", "15:00 UTC" (a time needs am/pm or minutes).
    private static let zonedTimePattern = CompiledPattern(
        #"(?<![\w:])(\d{1,2})(?::(\d{2}))?\s?([aApP]\.?[mM]\.?)?\s?\(?(\#(zoneNames))\)?(?![\w])"#)
    private static let numericDatePattern = CompiledPattern(#"(?<![\d/.-])(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})(?![\d/.:T-])"#)
    private static let japaneseDatePattern = CompiledPattern(#"(?:(\d{4})年)?(\d{1,2})月(\d{1,2})日"#)
    private static let englishDatePattern = CompiledPattern(
        #"\b(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)[a-z]*\.? (\d{1,2})(?:st|nd|rd|th)?(?:,? (\d{4}))?\b"#)

    /// Common abbreviations with a fixed offset in seconds; the generic US
    /// names (PT, ET…) use their region's current rules.
    private static let zoneOffsets: [String: Int] = [
        "UTC": 0, "GMT": 0, "Z": 0,
        "PST": -8 * 3600, "PDT": -7 * 3600, "MST": -7 * 3600, "MDT": -6 * 3600,
        "CST": -6 * 3600, "CDT": -5 * 3600, "EST": -5 * 3600, "EDT": -4 * 3600,
        "BST": 3600, "CET": 3600, "CEST": 2 * 3600, "IST": 5 * 3600 + 1800,
        "SGT": 8 * 3600, "HKT": 8 * 3600, "JST": 9 * 3600, "KST": 9 * 3600,
        "AEST": 10 * 3600, "AEDT": 11 * 3600,
        "PT": 0, "MT": 0, "CT": 0, "ET": 0   // resolved by region below
    ]
    private static let regionZones = ["PT": "America/Los_Angeles", "MT": "America/Denver", "CT": "America/Chicago", "ET": "America/New_York"]

    private static func zone(named name: String) -> TimeZone? {
        if let identifier = regionZones[name] { return TimeZone(identifier: identifier) }
        return zoneOffsets[name].flatMap { TimeZone(secondsFromGMT: $0) }
    }

    private static let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

    private static func monthNumber(_ name: String) -> Int? {
        months.firstIndex(of: String(name.lowercased().prefix(3))).map { $0 + 1 }
    }

    private func int(_ groups: [String?], _ index: Int) -> Int? {
        groups.count > index ? groups[index].flatMap { Int($0) } : nil
    }

    // MARK: Conversions

    private func zonedTime(_ groups: [String?], original: Substring) -> UnitConversion? {
        guard groups.count > 4, let hourText = groups[1], var hour = Int(hourText),
              let zoneName = groups[4], let source = Self.zone(named: zoneName) else { return nil }
        let minute = groups[2].flatMap { Int($0) } ?? 0
        let meridiem = groups[3]?.lowercased().first
        guard meridiem != nil || groups[2] != nil else { return nil }   // "3 ET" is too ambiguous
        if let meridiem {
            guard (1...12).contains(hour) else { return nil }
            if meridiem == "p", hour < 12 { hour += 12 }
            if meridiem == "a", hour == 12 { hour = 0 }
        }
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        var sourceCalendar = Calendar(identifier: .gregorian)
        sourceCalendar.timeZone = source
        var components = sourceCalendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute
        guard let instant = sourceCalendar.date(from: components),
              source.secondsFromGMT(for: instant) != timeZone.secondsFromGMT(for: instant) else { return nil }
        let sourceDay = sourceCalendar.startOfDay(for: instant)
        let targetComponents = calendar.dateComponents([.year, .month, .day], from: instant)
        let sourceComponents = sourceCalendar.dateComponents([.year, .month, .day], from: sourceDay)
        let shift = dayDifference(from: sourceComponents, to: targetComponents)
        return UnitConversion(original: String(original).trimmingCharacters(in: .whitespaces),
                              converted: clock(instant, dayShift: shift))
    }

    private func unix(_ groups: [String?]) -> UnitConversion? {
        guard groups.count > 1, let secondsText = groups[1], let seconds = Double(secondsText) else { return nil }
        let millis = groups.count > 2 ? groups[2] : nil
        let date = Date(timeIntervalSince1970: seconds + (millis.flatMap { Double($0) } ?? 0) / 1000)
        return UnitConversion(original: secondsText + (millis ?? ""), converted: dateTime(date))
    }

    private func iso(_ groups: [String?], original: Substring) -> UnitConversion? {
        guard groups.count > 7, let year = int(groups, 1), let month = int(groups, 2), let day = int(groups, 3),
              let hour = int(groups, 4), let minute = int(groups, 5), let zoneText = groups[7] else { return nil }
        let offset: Int
        if zoneText == "Z" {
            offset = 0
        } else {
            let digits = zoneText.dropFirst().replacingOccurrences(of: ":", with: "")
            guard digits.count == 4, let hours = Int(digits.prefix(2)), let minutes = Int(digits.suffix(2)) else { return nil }
            offset = (zoneText.hasPrefix("-") ? -1 : 1) * (hours * 3600 + minutes * 60)
        }
        guard let source = TimeZone(secondsFromGMT: offset) else { return nil }
        var sourceCalendar = Calendar(identifier: .gregorian)
        sourceCalendar.timeZone = source
        guard let instant = sourceCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute,
                                                                       second: int(groups, 6) ?? 0)),
              offset != timeZone.secondsFromGMT(for: instant) else { return nil }
        return UnitConversion(original: String(original), converted: dateTime(instant))
    }

    /// A calendar date as days from today, with the weekday.
    private func date(year: Int?, month: Int?, day: Int?, original: Substring) -> UnitConversion? {
        guard let month, let day, (1...12).contains(month), (1...31).contains(day) else { return nil }
        let today = calendar.dateComponents([.year, .month, .day], from: now)
        guard let currentYear = today.year else { return nil }
        var candidate = DateComponents(year: year ?? currentYear, month: month, day: day)
        guard calendar.date(from: candidate).map({ calendar.component(.day, from: $0) == day }) == true else { return nil }
        var days = dayDifference(from: today, to: candidate)
        if year == nil {
            // Without a year, the nearest occurrence (within about six months).
            if days > 183 { candidate.year = currentYear - 1 }
            if days < -183 { candidate.year = currentYear + 1 }
            days = dayDifference(from: today, to: candidate)
        }
        guard let instant = calendar.date(from: candidate) else { return nil }
        let weekday = calendar.component(.weekday, from: instant) - 1
        let weekdays = japanese ? ["日", "月", "火", "水", "木", "金", "土"] : ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let name = weekdays.indices.contains(weekday) ? weekdays[weekday] : ""
        return UnitConversion(original: String(original), converted: relative(days) + (japanese ? "（\(name)）" : " (\(name))"))
    }

    private func relative(_ days: Int) -> String {
        switch days {
        case 0: return japanese ? "今日" : "today"
        case 1: return japanese ? "明日" : "tomorrow"
        case -1: return japanese ? "昨日" : "yesterday"
        case 2...: return japanese ? "\(days)日後" : "in \(days) days"
        default: return japanese ? "\(-days)日前" : "\(-days) days ago"
        }
    }

    private func dayDifference(from start: DateComponents, to end: DateComponents) -> Int {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0) ?? utc.timeZone
        let strip = { (components: DateComponents) in DateComponents(year: components.year, month: components.month, day: components.day) }
        guard let from = utc.date(from: strip(start)), let to = utc.date(from: strip(end)) else { return 0 }
        return utc.dateComponents([.day], from: from, to: to).day ?? 0
    }

    // MARK: Formatting

    /// "日本時間" for Japanese readers in Japan, otherwise "UTC+9" / "UTC-5:30".
    var zoneLabel: String {
        let seconds = timeZone.secondsFromGMT(for: now)
        if japanese, seconds == 9 * 3600 { return "日本時間" }
        let sign = seconds < 0 ? "-" : "+"
        let hours = abs(seconds) / 3600
        let minutes = abs(seconds) % 3600 / 60
        return "UTC" + sign + "\(hours)" + (minutes == 0 ? "" : String(format: ":%02ld", minutes))
    }

    private func clock(_ instant: Date, dayShift: Int) -> String {
        let components = calendar.dateComponents([.hour, .minute], from: instant)
        let time = String(format: "%ld:%02ld", components.hour ?? 0, components.minute ?? 0)
        if japanese {
            let prefix = dayShift > 0 ? "翌日 " : (dayShift < 0 ? "前日 " : "")
            return "\(prefix)\(time)（\(zoneLabel)）"
        }
        let suffix = dayShift > 0 ? " (+1 day)" : (dayShift < 0 ? " (-1 day)" : "")
        return "\(time) \(zoneLabel)\(suffix)"
    }

    private func dateTime(_ instant: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: instant)
        let text = String(format: "%04ld-%02ld-%02ld %ld:%02ld", components.year ?? 0, components.month ?? 0, components.day ?? 0,
                          components.hour ?? 0, components.minute ?? 0)
        return japanese ? "\(text)（\(zoneLabel)）" : "\(text) \(zoneLabel)"
    }
}

/// Unit and time conversions together, as shown where the pointer rests.
public enum QuickConversions {
    public static func all(in text: String, targetLanguage: String, now: Date = Date(), timeZone: TimeZone = .current,
                           limit: Int = 3) -> [UnitConversion] {
        let units = UnitConverter.conversions(in: text, targetLanguage: targetLanguage, limit: limit)
        let times = TimeConverter(now: now, timeZone: timeZone, targetLanguage: targetLanguage).conversions(in: text, limit: limit)
        return Array((units + times).prefix(limit))
    }
}
