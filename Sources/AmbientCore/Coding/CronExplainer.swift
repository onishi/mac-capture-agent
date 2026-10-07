import Foundation

/// Explains cron schedules in plain words (SPEC LA-22). Rules only;
/// common shapes are described, anything else is left alone (nil).
public enum CronExplainer {
    /// Five whitespace-separated cron fields with at least one "*" or "/", or a macro.
    private static let fivePattern = CompiledPattern(
        #"(?<![\S])([\d*/,\-]+)\s+([\d*/,\-]+)\s+([\d*/,\-?LW]+)\s+([\d*/,\-A-Za-z]+)\s+([\d*/,\-A-Za-z?L#]+)(?![\S])"#)
    private static let macroPattern = CompiledPattern(#"(?<![\S])@(yearly|annually|monthly|weekly|daily|midnight|hourly|reboot)(?![\S])"#)

    /// The first schedule in `text` and its explanation.
    public static func conversion(in text: String, targetLanguage: String) -> UnitConversion? {
        let japanese = LanguageCode.base(targetLanguage) == "ja"
        if let groups = macroPattern.captures(in: text).first, groups.count > 1, let macro = groups[1] {
            return UnitConversion(original: "@" + macro, converted: describe(macro: macro, japanese: japanese))
        }
        for groups in fivePattern.captures(in: text) {
            guard groups.count == 6, let whole = groups[0] else { continue }
            let fields = groups[1...5].compactMap { $0 }
            guard fields.count == 5, whole.contains("*") || whole.contains("/"),
                  let explanation = explain(fields, japanese: japanese) else { continue }
            return UnitConversion(original: whole.trimmingCharacters(in: .whitespaces), converted: explanation)
        }
        return nil
    }

    static func describe(macro: String, japanese: Bool) -> String {
        switch macro {
        case "yearly", "annually": return japanese ? "毎年 1月1日 0:00" : "every year on Jan 1 at 0:00"
        case "monthly": return japanese ? "毎月 1日 0:00" : "every month on the 1st at 0:00"
        case "weekly": return japanese ? "毎週 日曜 0:00" : "every Sunday at 0:00"
        case "daily", "midnight": return japanese ? "毎日 0:00" : "every day at 0:00"
        case "hourly": return japanese ? "毎時 0分" : "every hour at :00"
        default: return japanese ? "起動時に 1 回" : "once at startup"
        }
    }

    /// minute hour day-of-month month day-of-week.
    static func explain(_ fields: [String], japanese: Bool) -> String? {
        guard fields.count == 5 else { return nil }
        let (minute, hour, day, month, weekday) = (fields[0], fields[1], fields[2], fields[3], fields[4])
        guard month == "*" else { return nil }   // month-specific schedules are rare; keep it honest

        func step(_ field: String) -> Int? {
            guard field.hasPrefix("*/"), let value = Int(field.dropFirst(2)), value > 0 else { return nil }
            return value
        }
        let minuteValue = Int(minute)
        let hourValue = Int(hour)
        let when: String
        if minute == "*", hour == "*" {
            when = japanese ? "毎分" : "every minute"
        } else if let every = step(minute), hour == "*" {
            when = japanese ? "\(every)分ごと" : "every \(every) minutes"
        } else if let minuteValue, (0...59).contains(minuteValue), hour == "*" {
            when = japanese ? "毎時 \(minuteValue)分" : String(format: "every hour at :%02ld", minuteValue)
        } else if let minuteValue, (0...59).contains(minuteValue), let every = step(hour) {
            when = japanese ? "\(every)時間ごと（\(minuteValue)分）" : String(format: "every %ld hours at :%02ld", every, minuteValue)
        } else if let minuteValue, (0...59).contains(minuteValue), let hourValue, (0...23).contains(hourValue) {
            when = String(format: "%ld:%02ld", hourValue, minuteValue)
        } else if let minuteValue, (0...59).contains(minuteValue), hour.contains(",") {
            let hours = hour.split(separator: ",").compactMap { Int($0) }
            guard !hours.isEmpty, hours.allSatisfy({ (0...23).contains($0) }) else { return nil }
            when = hours.map { String(format: "%ld:%02ld", $0, minuteValue) }.joined(separator: japanese ? "・" : ", ")
        } else {
            return nil
        }
        let atTime = hourValue != nil || hour.contains(",")

        var dayPart = ""
        if weekday != "*" && weekday != "?" {
            guard let days = weekdays(weekday, japanese: japanese) else { return nil }
            dayPart = japanese ? "毎週 \(days) " : "every \(days) "
        } else if day != "*" && day != "?" {
            guard let dayValue = Int(day), (1...31).contains(dayValue) else { return nil }
            dayPart = japanese ? "毎月 \(dayValue)日 " : "every month on day \(dayValue) "
        } else if atTime {
            dayPart = japanese ? "毎日 " : "every day "
        }
        if atTime {
            return japanese ? dayPart + when : dayPart + "at " + when
        }
        return japanese ? dayPart + when : (dayPart.isEmpty ? when : dayPart + when)
    }

    static func weekdays(_ field: String, japanese: Bool) -> String? {
        let names = japanese ? ["日", "月", "火", "水", "木", "金", "土"] : ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let aliases = ["sun": 0, "mon": 1, "tue": 2, "wed": 3, "thu": 4, "fri": 5, "sat": 6]
        func day(_ token: Substring) -> Int? {
            if let value = Int(token), (0...7).contains(value) { return value % 7 }
            return aliases[token.lowercased()]
        }
        var parts: [String] = []
        for item in field.split(separator: ",") {
            let bounds = item.split(separator: "-")
            if bounds.count == 2, let start = day(bounds[0]), let end = day(bounds[1]) {
                parts.append(names[start] + (japanese ? "〜" : "–") + names[end])
            } else if bounds.count == 1, let single = day(bounds[0]) {
                parts.append(names[single])
            } else {
                return nil
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: japanese ? "・" : ", ")
    }
}
