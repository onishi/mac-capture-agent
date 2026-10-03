import Foundation
import NaturalLanguage

/// `LanguageIdentifying` backed by `NLLanguageRecognizer`.
/// A new recognizer is created per call because it is not thread-safe.
struct NLLanguageIdentifier: LanguageIdentifying {
    func identify(_ text: String) -> LanguageGuess? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let best = recognizer.languageHypotheses(withMaximum: 3).max(by: { $0.value < $1.value }) else {
            return nil
        }
        return LanguageGuess(code: best.key.rawValue, confidence: best.value)
    }
}
