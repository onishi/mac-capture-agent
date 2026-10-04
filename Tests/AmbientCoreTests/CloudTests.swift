import XCTest
@testable import AmbientCore

final class NetworkPolicyTests: XCTestCase {
    let gemini = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/x:generateContent")!

    func testNothingIsSentBeforeOptIn() {
        XCTAssertEqual(NetworkPolicy(cloudEnabled: false, hasAPIKey: true, performanceMode: .balanced).denial(for: gemini), .notOptedIn)
        XCTAssertEqual(NetworkPolicy(cloudEnabled: true, hasAPIKey: false, performanceMode: .balanced).denial(for: gemini), .noAPIKey)
        XCTAssertNil(NetworkPolicy(cloudEnabled: true, hasAPIKey: true, performanceMode: .balanced).denial(for: gemini))
    }

    func testBatteryModeAndHostAllowList() {
        let policy = NetworkPolicy(cloudEnabled: true, hasAPIKey: true, performanceMode: .battery)
        XCTAssertEqual(policy.denial(for: gemini), .batteryMode)
        let open = NetworkPolicy(cloudEnabled: true, hasAPIKey: true, performanceMode: .performance)
        XCTAssertEqual(open.denial(for: URL(string: "https://example.com/upload")!), .hostNotAllowed)
        XCTAssertEqual(open.denial(for: URL(string: "http://generativelanguage.googleapis.com/x")!), .insecure)
    }
}

final class GeminiAPITests: XCTestCase {
    func testEndpointRejectsInjectedModelNames() {
        XCTAssertEqual(GeminiAPI.endpoint(model: "gemini-2.5-flash")?.absoluteString,
                       "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent")
        XCTAssertNil(GeminiAPI.endpoint(model: "x/../../evil"))
        XCTAssertNil(GeminiAPI.endpoint(model: " "))
    }

    func testRequestBodyShape() throws {
        let body = try GeminiAPI.requestBody(system: "sys", parts: [.text("hello"), .jpeg(Data([0xFF, 0xD8]))], schema: IdentificationAnswer.schema)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let contents = try XCTUnwrap(json["contents"] as? [[String: Any]])
        let parts = try XCTUnwrap(contents.first?["parts"] as? [[String: Any]])
        XCTAssertEqual(parts.first?["text"] as? String, "hello")
        let inline = try XCTUnwrap(parts.last?["inline_data"] as? [String: Any])
        XCTAssertEqual(inline["mime_type"] as? String, "image/jpeg")
        XCTAssertEqual(inline["data"] as? String, Data([0xFF, 0xD8]).base64EncodedString())
        let config = try XCTUnwrap(json["generationConfig"] as? [String: Any])
        XCTAssertEqual(config["responseMimeType"] as? String, "application/json")
        XCTAssertNotNil(config["responseSchema"])
        XCTAssertNotNil(json["system_instruction"])
    }

    func testDecodeAnswer() throws {
        let answer = #"{"category":"animal","name":"カワセミ","scientificName":"Alcedo atthis","facts":["鳥綱 ブッポウソウ目 カワセミ科"],"confidence":0.91}"#
        let response = try JSONSerialization.data(withJSONObject: [
            "candidates": [["content": ["parts": [["text": answer]]], "finishReason": "STOP"]]
        ])
        let decoded = try GeminiAPI.decodeAnswer(IdentificationAnswer.self, from: response)
        XCTAssertEqual(decoded.name, "カワセミ")
        XCTAssertEqual(decoded.scientificName, "Alcedo atthis")
    }

    func testDecodeErrors() throws {
        let blocked = try JSONSerialization.data(withJSONObject: ["promptFeedback": ["blockReason": "SAFETY"]])
        XCTAssertThrowsError(try GeminiAPI.decodeAnswer(IdentificationAnswer.self, from: blocked)) { error in
            XCTAssertEqual(error as? GeminiAPI.APIError, .blocked("SAFETY"))
        }
        let malformed = try JSONSerialization.data(withJSONObject: ["candidates": [["content": ["parts": [["text": "not json"]]]]]])
        XCTAssertThrowsError(try GeminiAPI.decodeAnswer(IdentificationAnswer.self, from: malformed)) { error in
            XCTAssertEqual(error as? GeminiAPI.APIError, .malformedJSON)
        }
        XCTAssertThrowsError(try GeminiAPI.decodeAnswer(IdentificationAnswer.self, from: Data("[]".utf8)))
    }

    func testInstructionsForbidIdentifyingPeopleFromImages() {
        XCTAssertTrue(IdentificationAnswer.instructions(targetLanguage: "ja").contains("Never identify or describe people"))
        XCTAssertTrue(PublicFigureAnswer.instructions(targetLanguage: "ja").contains("Never guess"))
    }
}

final class IdentificationPolicyTests: XCTestCase {
    func answer(_ category: String, _ name: String, confidence: Double) -> IdentificationAnswer {
        IdentificationAnswer(category: category, name: name, scientificName: "", facts: [], confidence: confidence)
    }

    func testAcceptsOnlyConfidentMatchingCategory() {
        XCTAssertTrue(IdentificationPolicy.accept(answer("animal", "カワセミ", confidence: 0.9), hint: .animal))
        XCTAssertFalse(IdentificationPolicy.accept(answer("animal", "カワセミ", confidence: 0.4), hint: .animal))
        XCTAssertFalse(IdentificationPolicy.accept(answer("none", "", confidence: 0.9), hint: .animal))
        XCTAssertFalse(IdentificationPolicy.accept(answer("plant", "バラ", confidence: 0.9), hint: .animal), "category mismatch")
    }

    func testHedging() {
        XCTAssertEqual(IdentificationPolicy.displayName("カワセミ", confidence: 0.9, language: "ja"), "カワセミ")
        XCTAssertEqual(IdentificationPolicy.displayName("カワセミ", confidence: 0.6, language: "ja"), "カワセミ（の可能性があります）")
        XCTAssertEqual(IdentificationPolicy.displayName("Kingfisher", confidence: 0.6, language: "en"), "Kingfisher (possibly)")
    }

    func testPublicFigureMustMatchNameOnScreen() {
        let cate = PublicFigureAnswer(isPublicFigure: true, name: "Cate Blanchett", role: "Actor", knownFor: ["TÁR"], confidence: 0.95)
        XCTAssertTrue(IdentificationPolicy.accept(cate, nameOnScreen: "Cate Blanchett"))
        XCTAssertTrue(IdentificationPolicy.accept(cate, nameOnScreen: "Blanchett"))
        XCTAssertFalse(IdentificationPolicy.accept(cate, nameOnScreen: "John Smith"), "answer about someone else")
        var private_ = cate
        private_.isPublicFigure = false
        XCTAssertFalse(IdentificationPolicy.accept(private_, nameOnScreen: "Cate Blanchett"))
        var unsure = cate
        unsure.confidence = 0.6
        XCTAssertFalse(IdentificationPolicy.accept(unsure, nameOnScreen: "Cate Blanchett"))
    }

    func testBrowserURLs() {
        XCTAssertEqual(IdentificationPolicy.webSearchURL(for: "Alcedo atthis")?.absoluteString, "https://www.google.com/search?q=Alcedo%20atthis")
        XCTAssertEqual(IdentificationPolicy.wikipediaURL(for: "カワセミ", language: "ja")?.host, "ja.wikipedia.org")
        XCTAssertEqual(IdentificationPolicy.wikipediaURL(for: "x", language: "zh-Hans")?.host, "zh.wikipedia.org")
    }
}
