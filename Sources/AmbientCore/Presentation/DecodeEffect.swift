import Foundation

/// "Decrypting" text effect: characters lock in from left to right while the
/// rest cycle through cipher glyphs. Pure function of progress, so it can be
/// driven by any clock (SwiftUI `TimelineView`) and tested.
public enum DecodeEffect {
    public static let latinGlyphs = Array("ABCDEFGHJKLMNPQRSTUVWXYZ0123456789#%&@$*+=<>/")
    public static let cjkGlyphs = Array("アイウエオカキクケコサシスセソタチツテトナニヌネノ01")

    /// - Parameters:
    ///   - text: the final text.
    ///   - progress: 0 (fully scrambled) ... 1 (fully decoded).
    ///   - tick: changes the scrambled glyphs over time.
    public static func frame(of text: String, progress: Double, tick: Int) -> String {
        let characters = Array(text)
        guard !characters.isEmpty else { return text }
        let clamped = min(max(progress, 0), 1)
        if clamped >= 1 { return text }
        let revealed = Int((Double(characters.count) * clamped).rounded(.down))
        var output = String()
        output.reserveCapacity(text.utf8.count)
        for (index, character) in characters.enumerated() {
            if index < revealed || character.isWhitespace || character.isNewline || character.isPunctuation {
                output.append(character)
                continue
            }
            let isCJK = character.unicodeScalars.first.map(TextHeuristics.isCJK) ?? false
            let glyphs = isCJK ? cjkGlyphs : latinGlyphs
            let seed = abs((index &* 31) &+ (tick &* 17) &+ index &* tick)
            output.append(glyphs[seed % glyphs.count])
        }
        return output
    }

    /// Progress for an animation of `duration` seconds started `elapsed` seconds ago (ease-out).
    public static func progress(elapsed: TimeInterval, duration: TimeInterval) -> Double {
        guard duration > 0 else { return 1 }
        let t = min(max(elapsed / duration, 0), 1)
        return 1 - pow(1 - t, 2)
    }
}

/// Short operation codes for the HUD chrome ("TGT-3F2A").
public enum HUDCodename {
    public static func targetCode(for id: UUID) -> String {
        "TGT-" + id.uuidString.replacingOccurrences(of: "-", with: "").prefix(4)
    }

    /// "FR ▸ JA"
    public static func route(source: String?, target: String?) -> String {
        let s = source.map { LanguageCode.base($0).uppercased() } ?? "??"
        let t = target.map { LanguageCode.base($0).uppercased() } ?? "??"
        return "\(s) ▸ \(t)"
    }

    /// Segmented meter, e.g. 0.73 → 7 of 10 segments.
    public static func meterSegments(confidence: Double, segments: Int = 10) -> Int {
        guard segments > 0 else { return 0 }
        return Int((min(max(confidence, 0), 1) * Double(segments)).rounded())
    }
}
