import Foundation

/// Builds Gemini `generateContent` requests and parses responses. Pure, so the
/// wire format is unit-tested; the app only performs the HTTP call.
public enum GeminiAPI {
    public static let defaultModel = "gemini-2.5-flash"

    public enum Part: Sendable, Equatable {
        case text(String)
        case jpeg(Data)
    }

    public enum APIError: Error, Equatable {
        case invalidResponse
        case blocked(String)
        case emptyCandidate
        case malformedJSON
    }

    public static func endpoint(model: String) -> URL? {
        let safeModel = model.trimmingCharacters(in: .whitespaces)
        guard !safeModel.isEmpty, safeModel.allSatisfy({ $0.isLetter || $0.isNumber || "-._".contains($0) }) else { return nil }
        return URL(string: "https://\(NetworkPolicy.geminiHost)/v1beta/models/\(safeModel):generateContent")
    }

    /// JSON body for a request with structured (JSON schema) output.
    public static func requestBody(system: String, parts: [Part], schema: [String: Any], temperature: Double = 0.2) throws -> Data {
        let contentParts: [[String: Any]] = parts.map { part in
            switch part {
            case .text(let text):
                return ["text": text]
            case .jpeg(let data):
                return ["inline_data": ["mime_type": "image/jpeg", "data": data.base64EncodedString()]]
            }
        }
        let body: [String: Any] = [
            "system_instruction": ["parts": [["text": system]]],
            "contents": [["role": "user", "parts": contentParts]],
            "generationConfig": [
                "temperature": temperature,
                "responseMimeType": "application/json",
                "responseSchema": schema
            ]
        ]
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }

    /// Request body grounded with Google Search. Structured output can't be
    /// combined with search grounding, so the JSON is requested in the prompt.
    public static func groundedRequestBody(system: String, prompt: String, temperature: Double = 0.2) throws -> Data {
        let body: [String: Any] = [
            "system_instruction": ["parts": [["text": system]]],
            "contents": [["role": "user", "parts": [["text": prompt]]]],
            "tools": [["google_search": [String: Any]()]],
            "generationConfig": ["temperature": temperature]
        ]
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }

    /// The first JSON object in free text (handles ```json fences and prose around it).
    public static func extractJSONObject(from text: String) -> Data? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var index = start
        while index < text.endIndex {
            let character = text[index]
            if inString {
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { inString = false }
            } else if character == "\"" {
                inString = true
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    return String(text[start...index]).data(using: .utf8)
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    /// Extracts the model's JSON answer from a `generateContent` response.
    /// Works for structured output and for JSON embedded in grounded text answers.
    public static func decodeAnswer<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw APIError.invalidResponse }
        if let feedback = root["promptFeedback"] as? [String: Any], let reason = feedback["blockReason"] as? String {
            throw APIError.blocked(reason)
        }
        guard let candidates = root["candidates"] as? [[String: Any]], let first = candidates.first else { throw APIError.emptyCandidate }
        if let reason = first["finishReason"] as? String, reason == "SAFETY" || reason == "PROHIBITED_CONTENT" {
            throw APIError.blocked(reason)
        }
        guard let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else { throw APIError.emptyCandidate }
        let text = parts.compactMap { $0["text"] as? String }.joined()
        guard !text.isEmpty else { throw APIError.emptyCandidate }
        if let json = text.data(using: .utf8), let decoded = try? JSONDecoder().decode(T.self, from: json) {
            return decoded
        }
        guard let embedded = extractJSONObject(from: text), let decoded = try? JSONDecoder().decode(T.self, from: embedded) else {
            throw APIError.malformedJSON
        }
        return decoded
    }
}

// MARK: - Schemas and answers

/// What Gemini sees in a cropped image (animals, plants, landmarks — never people).
public struct IdentificationAnswer: Codable, Sendable, Equatable {
    public var category: String          // "animal" | "plant" | "landmark" | "food" | "product" | "none"
    public var name: String              // common name in the user's language
    public var scientificName: String    // or location for landmarks; may be empty
    public var facts: [String]           // up to 3 short facts
    public var confidence: Double        // 0...1

    public static var schema: [String: Any] {
        [
            "type": "OBJECT",
            "properties": [
                "category": ["type": "STRING", "enum": ["animal", "plant", "landmark", "food", "product", "none"]],
                "name": ["type": "STRING"],
                "scientificName": ["type": "STRING"],
                "facts": ["type": "ARRAY", "items": ["type": "STRING"]],
                "confidence": ["type": "NUMBER"]
            ],
            "required": ["category", "name", "scientificName", "facts", "confidence"]
        ]
    }

    public static func instructions(targetLanguage: String) -> String {
        """
        Identify the main animal, plant, landmark, dish (food) or product in the image. Never identify or describe people. \
        If the subject is a person, text, or unclear, return category "none". \
        For animals and plants give the common name and the scientific name; for landmarks give the name \
        and its city/country in scientificName; for food give the dish name and its cuisine/region; for products give \
        the product name and the brand (logos count as the brand). Give at most 3 short facts \
        (taxonomy, habitat, architect, year, ingredients, maker). \
        confidence is your probability that the name is correct. Answer in the language with code "\(targetLanguage)" \
        (scientific names stay in Latin).
        """
    }
}

/// Whether a person *named on screen* is a public figure, and who they are.
public struct PublicFigureAnswer: Codable, Sendable, Equatable {
    public var isPublicFigure: Bool
    public var name: String
    public var role: String
    public var knownFor: [String]
    public var confidence: Double

    public static var schema: [String: Any] {
        [
            "type": "OBJECT",
            "properties": [
                "isPublicFigure": ["type": "BOOLEAN"],
                "name": ["type": "STRING"],
                "role": ["type": "STRING"],
                "knownFor": ["type": "ARRAY", "items": ["type": "STRING"]],
                "confidence": ["type": "NUMBER"]
            ],
            "required": ["isPublicFigure", "name", "role", "knownFor", "confidence"]
        ]
    }

    public static func instructions(targetLanguage: String) -> String {
        """
        A name appears on the user's screen (caption, subtitle, title). Decide whether it refers to a widely known \
        public figure (actor, musician, athlete, politician, executive, author…) and, if so, who. \
        Use only well-established public information. If the person is a private individual, not clearly identifiable \
        from the name and context, or you are unsure, set isPublicFigure to false and leave other fields empty. \
        Never guess. role: one short phrase. knownFor: up to 3 works or achievements. \
        Answer in the language with code "\(targetLanguage)" (keep proper names as commonly written).
        """
    }
}
