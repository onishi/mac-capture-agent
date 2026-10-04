import Foundation

/// Kinds of things the app recognizes by name.
public enum EntityType: String, Sendable, Codable, CaseIterable {
    case person
    case organization
    case place
    case term
}

/// A named thing found in on-screen text.
public struct ExtractedEntity: Sendable, Equatable, Hashable {
    public let type: EntityType
    public let name: String
    public let canonicalName: String

    public init(type: EntityType, name: String) {
        self.type = type
        self.name = name
        self.canonicalName = EntityName.canonical(name)
    }
}

public enum EntityName {
    /// Canonical form used as identity: width/compatibility folded (NFKC),
    /// case folded, whitespace collapsed, surrounding punctuation removed.
    public static func canonical(_ name: String) -> String {
        let folded = name.precomposedStringWithCompatibilityMapping.lowercased()
        let trimmed = folded.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines).union(.symbols))
        return TextHeuristics.normalized(trimmed)
    }
}
