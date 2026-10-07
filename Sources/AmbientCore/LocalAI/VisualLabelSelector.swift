import Foundation

/// One image-classification label (Vision's `VNClassifyImageRequest` taxonomy).
public struct VisualLabel: Sendable, Equatable, Hashable {
    public let identifier: String
    public let confidence: Double

    public init(identifier: String, confidence: Double) {
        self.identifier = identifier
        self.confidence = confidence
    }

    /// "golden_retriever" → "golden retriever".
    public var readable: String {
        identifier.replacingOccurrences(of: "_", with: " ")
    }
}

/// Picks the labels worth handing to the local model. The classifier's
/// taxonomy is hierarchical ("animal" → "mammal" → "dog" → "retriever"); the
/// generic levels tell the model nothing, so only specific labels are kept.
public enum VisualLabelSelector {
    public static let minimumConfidence = 0.3
    public static let maximumLabels = 5

    /// Labels too generic to name anything.
    public static let genericLabels: Set<String> = [
        "animal", "mammal", "vertebrate", "wildlife", "pet", "bird", "fish", "insect", "reptile", "canine", "feline",
        "plant", "flower", "tree", "foliage", "leaf", "grass", "blossom", "vegetation", "garden",
        "food", "dish", "meal", "produce", "fruit", "vegetable", "dessert", "drink", "beverage", "baked_goods",
        "structure", "building", "architecture", "landmark", "monument", "cityscape", "outdoor", "indoor", "sky",
        "land", "water", "water_body", "nature", "people", "person", "adult", "child", "crowd", "portrait",
        "machine", "vehicle", "conveyance", "consumer_electronics", "electronics", "object", "material", "texture",
        "document", "text", "screenshot", "printed_page", "art", "illustration", "cartoon", "graphic_design", "colors"
    ]

    /// Specific labels of the hinted category, most confident first.
    /// Falls back to a generic label of that category so the model at least
    /// knows "bird" (it may then answer with a safe, generic name).
    public static func select(_ labels: [VisualLabel], for hint: VisualCategory) -> [VisualLabel] {
        let usable = labels
            .filter { $0.confidence >= minimumConfidence }
            .sorted { $0.confidence > $1.confidence }
        let ofCategory = usable.filter { hint == .unknown || VisualCategoryMapper.category(for: $0.identifier) == hint || isSpecificUnmapped($0, hint: hint, all: usable) }
        let specific = ofCategory.filter { !genericLabels.contains($0.identifier.lowercased()) }
        if !specific.isEmpty { return Array(specific.prefix(maximumLabels)) }
        return Array(ofCategory.prefix(1))
    }

    /// The best confidence among the selected labels (0 when none).
    public static func topConfidence(_ labels: [VisualLabel]) -> Double {
        labels.map(\.confidence).max() ?? 0
    }

    /// Specific labels the keyword mapper does not know ("kingfisher",
    /// "sagrada_familia") count for the hinted category when the hint itself
    /// came from this classification.
    private static func isSpecificUnmapped(_ label: VisualLabel, hint: VisualCategory, all: [VisualLabel]) -> Bool {
        guard VisualCategoryMapper.category(for: label.identifier) == .unknown,
              !genericLabels.contains(label.identifier.lowercased()) else { return false }
        return all.contains { VisualCategoryMapper.category(for: $0.identifier) == hint }
    }
}
