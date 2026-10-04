import XCTest
@testable import AmbientCore

final class MediaTitleParserTests: XCTestCase {
    func parse(_ title: String, url: String? = nil, bundle: String = "com.google.Chrome") -> MediaReference? {
        MediaTitleParser.parse(windowTitle: title, url: url.flatMap(URL.init(string:)), bundleIdentifier: bundle)
    }

    func testStreamingTitles() {
        XCTAssertEqual(parse("葬送のフリーレン 第5話 | dアニメストア"),
                       MediaReference(site: .dAnime, title: "葬送のフリーレン", episode: 5, season: nil))
        XCTAssertEqual(parse("(3) Inception - Official Trailer - YouTube"),
                       MediaReference(site: .youtube, title: "Inception - Official Trailer", episode: nil, season: nil))
        XCTAssertEqual(parse("Frieren: Beyond Journey's End S1E12 - Crunchyroll"),
                       MediaReference(site: .crunchyroll, title: "Frieren: Beyond Journey's End", episode: 12, season: 1))
        XCTAssertEqual(parse("Dark Season 2 Episode 3 | Netflix")?.season, 2)
        XCTAssertEqual(parse("Dark Season 2 Episode 3 | Netflix")?.episode, 3)
        XCTAssertEqual(parse("Watch", url: "https://www.netflix.com/watch/1234")?.site, .netflix)
    }

    func testNonMediaAndHomePages() {
        XCTAssertNil(parse("GitHub - groue/GRDB.swift"))
        XCTAssertNil(parse("YouTube"))
        XCTAssertNil(parse("Home - YouTube"))
    }

    func testMediaApps() {
        XCTAssertEqual(MediaTitleParser.parse(windowTitle: "Oppenheimer", url: nil, bundleIdentifier: "com.apple.TV")?.site, .appleTV)
    }

    func testWorkKeyIgnoresEpisode() {
        XCTAssertEqual(parse("葬送のフリーレン 第5話 | dアニメストア")?.workKey, parse("葬送のフリーレン 第6話 | dアニメストア")?.workKey)
    }

    func testMediaModeByTitle() {
        XCTAssertEqual(AppContextClassifier.classify(bundleIdentifier: "com.google.Chrome", windowTitle: "Inception - YouTube"), .media)
    }
}

final class SpoilerAndCastTests: XCTestCase {
    func testSpoilerInstructions() {
        XCTAssertTrue(SpoilerLevel.none.instruction(episode: 5).contains("STRICTLY NO SPOILERS"))
        XCTAssertTrue(SpoilerLevel.uptoCurrent.instruction(episode: 5).contains("episode 5"))
        XCTAssertEqual(SpoilerLevel.uptoCurrent.instruction(episode: nil), SpoilerLevel.none.instruction(episode: nil), "unknown position → strict")
        XCTAssertTrue(MediaInfoAnswer.instructions(spoiler: .uptoCurrent, episode: 3, targetLanguage: "ja").contains("episode 3"))
    }

    func testCastMatching() {
        let cast = [CastMember(character: "フリーレン", performer: "種﨑敦美"), CastMember(character: "Fern", performer: "Kana Ichinose")]
        XCTAssertEqual(CastMatcher.matches(cast, in: "フリーレン「行こうか」").map(\.character), ["フリーレン"])
        XCTAssertEqual(CastMatcher.matches(cast, in: "Fern: Lord Frieren!").map(\.character), ["Fern"])
        XCTAssertTrue(CastMatcher.matches(cast, in: "nothing here").isEmpty)
    }
}

final class NewsTests: XCTestCase {
    func testNewsArticleDetection() {
        XCTAssertTrue(NewsDetector.isNewsArticle(URL(string: "https://www3.nhk.or.jp/news/html/20261004/k10014.html")))
        XCTAssertFalse(NewsDetector.isNewsArticle(URL(string: "https://www3.nhk.or.jp/")), "front page")
        XCTAssertFalse(NewsDetector.isNewsArticle(URL(string: "https://github.com/a/b")))
        XCTAssertFalse(NewsDetector.isNewsArticle(nil))
    }

    func testHeadline() {
        XCTAssertEqual(NewsDetector.headline(from: "新しい宇宙望遠鏡が初画像を公開 | NHKニュース"), "新しい宇宙望遠鏡が初画像を公開")
        XCTAssertEqual(NewsDetector.headline(from: "Central bank raises rates again - Reuters"), "Central bank raises rates again")
        XCTAssertNil(NewsDetector.headline(from: "Reuters"))
    }

    func testGroundedJSONExtraction() throws {
        let text = "Here you go:\n```json\n{\"isNewsStory\": true, \"background\": \"It began in March {2026}.\", \"timeline\": [{\"date\": \"2026-03\", \"event\": \"Start\"}], \"relatedPeople\": [\"A\", \"B\"]}\n```"
        let data = try XCTUnwrap(GeminiAPI.extractJSONObject(from: text))
        let answer = try JSONDecoder().decode(NewsContextAnswer.self, from: data)
        XCTAssertEqual(answer.timeline.first?.date, "2026-03")
        XCTAssertEqual(answer.background, "It began in March {2026}.")
        XCTAssertNil(GeminiAPI.extractJSONObject(from: "no json"))

        let response = try JSONSerialization.data(withJSONObject: ["candidates": [["content": ["parts": [["text": text]]]]]])
        XCTAssertEqual(try GeminiAPI.decodeAnswer(NewsContextAnswer.self, from: response).relatedPeople, ["A", "B"])
    }

    func testGroundedBodyHasSearchTool() throws {
        let body = try GeminiAPI.groundedRequestBody(system: "s", prompt: "p")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertNotNil((json["tools"] as? [[String: Any]])?.first?["google_search"])
        XCTAssertNil((json["generationConfig"] as? [String: Any])?["responseSchema"])
    }

    func testProductCategory() {
        XCTAssertEqual(VisualCategoryMapper.category(for: "sneaker"), .product)
    }
}

final class MediaPolicyTests: XCTestCase {
    func testAcceptAndCacheName() {
        var answer = MediaInfoAnswer(isKnownWork: true, title: "葬送のフリーレン", kind: "anime", year: "2023", originalWork: "", cast: [], music: [], synopsis: "", confidence: 0.9)
        XCTAssertTrue(MediaPolicy.accept(answer))
        answer.confidence = 0.5
        XCTAssertFalse(MediaPolicy.accept(answer))
        let reference = MediaReference(site: .dAnime, title: "葬送のフリーレン", episode: 5, season: nil)
        XCTAssertEqual(MediaPolicy.cacheName(for: reference, spoiler: .uptoCurrent), "葬送のフリーレン#s1e5")
    }

    func testHeadlineKeywords() {
        let words = MediaPolicy.keywords(fromHeadline: "Central bank raises interest rates again")
        XCTAssertTrue(words.contains("interest"))
        XCTAssertFalse(words.contains("again") && words.count > 3)
    }
}
