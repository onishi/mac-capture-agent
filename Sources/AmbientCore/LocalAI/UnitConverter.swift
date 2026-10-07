import Foundation

/// A quantity found in text and its metric equivalent (LOCAL_AI.md LA-15).
public struct UnitConversion: Sendable, Equatable {
    /// The quantity as written ("72°F", "5 miles").
    public let original: String
    /// The converted quantity ("22.2 °C", "8.05 km").
    public let converted: String

    public init(original: String, converted: String) {
        self.original = original
        self.converted = converted
    }
}

/// Converts imperial / US customary quantities to metric. Rules only, so it
/// works on every Mac; shown only where the pointer rests (never on its own).
public enum UnitConverter {
    private struct Unit {
        let pattern: String
        let convert: (Double) -> (value: Double, unit: String)
    }

    private static let units: [Unit] = [
        Unit(pattern: #"°\s?F\b|℉|degrees? Fahrenheit"#) { (($0 - 32) * 5 / 9, "°C") },
        Unit(pattern: #"mph\b|miles? per hour"#) { ($0 * 1.609344, "km/h") },
        Unit(pattern: #"sq\.? ?ft\b|square (?:feet|foot)"#) { ($0 * 0.09290304, "m²") },
        Unit(pattern: #"miles?\b|mi\b"#) { meters($0 * 1609.344) },
        Unit(pattern: #"yards?\b|yd\b"#) { meters($0 * 0.9144) },
        Unit(pattern: #"feet\b|foot\b|ft\b|′"#) { meters($0 * 0.3048) },
        Unit(pattern: #"inch(?:es)?\b|in\.(?=\s|$)|″"#) { meters($0 * 0.0254) },
        Unit(pattern: #"pounds?\b|lbs?\b"#) { grams($0 * 453.59237) },
        Unit(pattern: #"ounces?\b|oz\b"#) { grams($0 * 28.349523125) },
        Unit(pattern: #"(?:US )?gallons?\b|gal\b"#) { ($0 * 3.785411784, "L") },
        Unit(pattern: #"fl\.? ?oz\b|fluid ounces?"#) { ($0 * 29.5735295625, "mL") },
        Unit(pattern: #"acres?\b"#) { ($0 * 0.40468564224, "ha") }
    ]

    /// Number (with thousands separators / decimals, optional minus) followed by a unit.
    private static let number = #"(?<![\w.])(-?\d{1,3}(?:,\d{3})+(?:\.\d+)?|-?\d+(?:\.\d+)?)"#
    private static let compiled: [(CompiledPattern, Unit)] = units.map { unit in
        (CompiledPattern(number + #"\s?(?:"# + unit.pattern + ")", caseInsensitive: true), unit)
    }

    /// Conversions for the quantities in `text`, in reading order, at most `limit`.
    /// Returns nothing when the user's language normally uses these units ("en").
    public static func conversions(in text: String, targetLanguage: String, limit: Int = 3) -> [UnitConversion] {
        guard LanguageCode.base(targetLanguage) != "en" else { return [] }
        var found: [(range: Range<String.Index>, conversion: UnitConversion)] = []
        for (pattern, unit) in compiled {
            for groups in pattern.captures(in: text) {
                guard let whole = groups.first ?? nil, let rawNumber = groups.count > 1 ? groups[1] : nil,
                      let value = Double(rawNumber.replacingOccurrences(of: ",", with: "")),
                      let range = text.range(of: whole) else { continue }
                // An earlier, longer unit already claimed this place ("mph" before "mi", "sq ft" before "ft").
                guard !found.contains(where: { $0.range.overlaps(range) }) else { continue }
                let result = unit.convert(value)
                found.append((range, UnitConversion(
                    original: whole.trimmingCharacters(in: .whitespaces),
                    converted: format(result.value) + " " + result.unit
                )))
            }
        }
        return found
            .sorted { $0.range.lowerBound < $1.range.lowerBound }
            .prefix(limit)
            .map { $0.conversion }
    }

    private static func meters(_ value: Double) -> (value: Double, unit: String) {
        let magnitude = abs(value)
        if magnitude >= 1000 { return (value / 1000, "km") }
        if magnitude < 1 { return (value * 100, "cm") }
        return (value, "m")
    }

    private static func grams(_ value: Double) -> (value: Double, unit: String) {
        abs(value) >= 1000 ? (value / 1000, "kg") : (value, "g")
    }

    /// Three significant digits, no trailing zeros ("22.2", "8.05", "1,610").
    static func format(_ value: Double) -> String {
        guard value.isFinite else { return "–" }
        let magnitude = abs(value)
        let decimals: Int
        switch magnitude {
        case 100...: decimals = 0
        case 10..<100: decimals = 1
        case 1..<10: decimals = 2
        default: decimals = 3
        }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = magnitude >= 10_000
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = decimals
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}
