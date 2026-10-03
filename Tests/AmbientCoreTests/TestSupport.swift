import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
@testable import AmbientCore

/// Language identifier that returns a fixed guess, or looks the text up in a table.
struct StubLanguageIdentifier: LanguageIdentifying {
    var table: [String: LanguageGuess] = [:]
    var fallback: LanguageGuess?

    func identify(_ text: String) -> LanguageGuess? {
        table[text] ?? fallback
    }
}

extension GrayscaleFrame {
    static func filled(width: Int, height: Int, value: UInt8) -> GrayscaleFrame {
        GrayscaleFrame(width: width, height: height, pixels: Array(repeating: value, count: width * height))!
    }

    /// Returns a copy with the given pixel rect set to `value`.
    func painting(x: Int, y: Int, width w: Int, height h: Int, value: UInt8) -> GrayscaleFrame {
        var copy = pixels
        for row in y..<min(y + h, height) {
            for col in x..<min(x + w, width) {
                copy[row * width + col] = value
            }
        }
        return GrayscaleFrame(width: width, height: height, pixels: copy)!
    }
}

func textRegion(_ text: String, y: CGFloat = 0.3, x: CGFloat = 0.1, height: CGFloat = 0.02, confidence: Float = 0.95) -> RecognizedTextRegion {
    RecognizedTextRegion(text: text, boundingBox: CGRect(x: x, y: y, width: 0.4, height: height), confidence: confidence)
}

func context(_ regions: [RecognizedTextRegion], bundle: String? = "com.apple.Safari", categories: [VisualCategory] = []) -> AnalysisContext {
    AnalysisContext(appName: "Safari", bundleIdentifier: bundle, windowTitle: "Page", textRegions: regions, visualCategories: categories)
}
