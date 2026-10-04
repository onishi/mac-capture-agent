import Foundation

/// Maps raw image-classification labels (e.g. Vision's `VNClassifyImageRequest`
/// taxonomy) onto the coarse `VisualCategory` used by the router.
public enum VisualCategoryMapper {
    private static let keywords: [(VisualCategory, [String])] = [
        (.person, ["people", "person", "adult", "child", "baby", "crowd", "portrait", "selfie", "face"]),
        (.animal, ["animal", "mammal", "dog", "cat", "bird", "fish", "horse", "insect", "reptile",
                   "canine", "feline", "pet", "wildlife", "butterfly", "cow", "sheep", "bear", "elephant"]),
        (.plant, ["plant", "flower", "tree", "foliage", "leaf", "grass", "blossom", "cactus",
                  "succulent", "garden", "moss", "fern"]),
        (.food, ["food", "dish", "meal", "fruit", "vegetable", "dessert", "drink", "beverage", "bread",
                 "cake", "sushi", "pizza", "salad", "coffee", "baked_goods"]),
        (.landmark, ["landmark", "monument", "tower", "bridge", "castle", "temple", "shrine", "cathedral",
                     "church", "skyscraper", "cityscape", "statue", "palace", "ruins", "pyramid"]),
        (.product, ["car", "automobile", "vehicle", "phone", "smartphone", "laptop", "computer", "watch", "shoe",
                    "sneaker", "handbag", "bag", "bottle", "camera", "headphones", "guitar", "bicycle", "furniture", "chair"]),
        (.text, ["document", "text", "screenshot", "printed_page", "handwriting", "sign", "poster", "menu"])
    ]

    public static func category(for label: String) -> VisualCategory {
        let normalized = label.lowercased()
        let tokens = Set(normalized.split(whereSeparator: { !$0.isLetter }).map(String.init))
        for (category, words) in keywords {
            for word in words where tokens.contains(word) || normalized == word {
                return category
            }
        }
        return .unknown
    }

    /// Maps `(label, confidence)` pairs to unique categories ordered by confidence.
    public static func categories(
        for labels: [(label: String, confidence: Float)],
        minimumConfidence: Float = 0.3
    ) -> [VisualCategory] {
        var result: [VisualCategory] = []
        for item in labels.sorted(by: { $0.confidence > $1.confidence }) where item.confidence >= minimumConfidence {
            let category = category(for: item.label)
            if category != .unknown && !result.contains(category) {
                result.append(category)
            }
        }
        return result
    }
}
