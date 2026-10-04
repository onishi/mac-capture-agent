import Foundation

/// Coarse category of what is visible in a region of the screen.
public enum VisualCategory: String, Sendable, CaseIterable, Equatable {
    case person
    case animal
    case plant
    case food
    case landmark
    case product
    case text
    case unknown
}
