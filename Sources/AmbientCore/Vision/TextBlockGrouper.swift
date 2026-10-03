import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Joins OCR lines that belong to the same paragraph so that a sentence
/// wrapped over several lines is evaluated (and translated) as a whole.
public struct TextBlockGrouper: Sendable {
    /// Maximum vertical gap between lines, relative to the line height.
    public var maximumLineGapRatio: CGFloat = 0.8
    /// Maximum difference of line heights (ratio) to be considered the same paragraph.
    public var maximumHeightRatio: CGFloat = 1.6
    /// Blocks are not grown beyond this many characters.
    public var maximumBlockLength: Int = 600

    public init() {}

    public func group(_ lines: [RecognizedTextRegion]) -> [RecognizedTextRegion] {
        let sorted = lines
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.boundingBox.minY == $1.boundingBox.minY ? $0.boundingBox.minX < $1.boundingBox.minX : $0.boundingBox.minY < $1.boundingBox.minY }

        var blocks: [Block] = []
        for line in sorted {
            if let index = blocks.lastIndex(where: { $0.accepts(line, grouper: self) }) {
                blocks[index].append(line)
            } else {
                blocks.append(Block(line: line))
            }
        }
        return blocks.map(\.region)
    }

    private struct Block {
        var text: String
        var box: CGRect
        var lastLine: CGRect
        var confidences: [Float]

        init(line: RecognizedTextRegion) {
            text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            box = line.boundingBox
            lastLine = line.boundingBox
            confidences = [line.confidence]
        }

        func accepts(_ line: RecognizedTextRegion, grouper: TextBlockGrouper) -> Bool {
            let candidate = line.boundingBox
            guard text.count + line.text.count <= grouper.maximumBlockLength else { return false }
            let lineHeight = max(lastLine.height, 0.0001)
            let heightRatio = max(candidate.height, lineHeight) / max(min(candidate.height, lineHeight), 0.0001)
            guard heightRatio <= grouper.maximumHeightRatio else { return false }
            let verticalGap = candidate.minY - lastLine.maxY
            guard verticalGap >= -lineHeight * 0.5, verticalGap <= lineHeight * grouper.maximumLineGapRatio else { return false }
            let overlap = min(candidate.maxX, box.maxX) - max(candidate.minX, box.minX)
            let alignedLeft = abs(candidate.minX - box.minX) <= lineHeight * 2
            return overlap > 0 && alignedLeft
        }

        mutating func append(_ line: RecognizedTextRegion) {
            text = TextBlockGrouper.join(text, line.text.trimmingCharacters(in: .whitespacesAndNewlines))
            box = box.union(line.boundingBox)
            lastLine = line.boundingBox
            confidences.append(line.confidence)
        }

        var region: RecognizedTextRegion {
            let mean = confidences.reduce(0, +) / Float(max(confidences.count, 1))
            return RecognizedTextRegion(text: text, boundingBox: box, confidence: mean)
        }
    }

    static func join(_ first: String, _ second: String) -> String {
        if first.hasSuffix("-"), let last = first.dropLast().last, last.isLetter {
            return String(first.dropLast()) + second
        }
        if let last = first.unicodeScalars.last, let next = second.unicodeScalars.first,
           TextHeuristics.isCJK(last) || TextHeuristics.isCJK(next) {
            return first + second
        }
        return first + " " + second
    }
}
