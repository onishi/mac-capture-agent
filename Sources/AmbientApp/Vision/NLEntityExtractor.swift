import Foundation
import NaturalLanguage

/// Person / place / organization names via `NLTagger` (on-device).
enum NLEntityExtractor {
    static func entities(in text: String, maximum: Int = 8) -> [ExtractedEntity] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        var result: [ExtractedEntity] = []
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType, options: options) { tag, range in
            let type: EntityType?
            switch tag {
            case .personalName: type = .person
            case .placeName: type = .place
            case .organizationName: type = .organization
            default: type = nil
            }
            if let type {
                let name = String(text[range])
                let entity = ExtractedEntity(type: type, name: name)
                if name.count >= 2, !result.contains(entity) {
                    result.append(entity)
                }
            }
            return result.count < maximum
        }
        return result
    }
}
