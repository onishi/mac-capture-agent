import XCTest
@testable import AmbientCore

final class CronExplainerTests: XCTestCase {
    func explain(_ text: String, _ language: String = "ja") -> String? {
        CronExplainer.conversion(in: text, targetLanguage: language).map { "\($0.original) → \($0.converted)" }
    }

    func testCommonSchedules() {
        XCTAssertEqual(explain("*/5 * * * * /usr/local/bin/backup.sh"), "*/5 * * * * → 5分ごと")
        XCTAssertEqual(explain("0 9 * * 1-5 run"), "0 9 * * 1-5 → 毎週 月〜金 9:00")
        XCTAssertEqual(explain("0 9 * * 1-5", "en"), "0 9 * * 1-5 → every Mon–Fri at 9:00")
        XCTAssertEqual(explain("30 2 * * *"), "30 2 * * * → 毎日 2:30")
        XCTAssertEqual(explain("0 0 1 * *"), "0 0 1 * * → 毎月 1日 0:00")
        XCTAssertEqual(explain("15 * * * *", "en"), "15 * * * * → every hour at :15")
        XCTAssertEqual(explain("0 */6 * * *"), "0 */6 * * * → 6時間ごと（0分）")
        XCTAssertEqual(explain("0 8,18 * * MON"), "0 8,18 * * MON → 毎週 月 8:00・18:00")
        XCTAssertEqual(explain("* * * * *", "en"), "* * * * * → every minute")
        XCTAssertEqual(explain("@daily /bin/x"), "@daily → 毎日 0:00")
    }

    func testCronWinsInQuickConversions() {
        XCTAssertEqual(QuickConversions.all(in: "*/5 * * * * curl -s 5 miles", targetLanguage: "ja").map(\.converted), ["5分ごと"])
    }

    func testIgnoresNonCron() {
        XCTAssertNil(explain("1 2 3 4 5"), "plain numbers")
        XCTAssertNil(explain("0 9 * 3 *"), "month-specific schedules are not described")
        XCTAssertNil(explain("rate */5 minutes"))
    }
}

final class StackTraceAnalyzerTests: XCTestCase {
    func testPythonUsesTheDeepestOwnFrame() {
        let trace = """
            Traceback (most recent call last):
              File "/Users/me/app/main.py", line 3, in <module>
              File "/Users/me/app/loader.py", line 12, in load
              File "/opt/venv/lib/python3.12/site-packages/requests/api.py", line 59, in get
            ModuleNotFoundError: No module named 'x'
            """
        XCTAssertEqual(StackTraceAnalyzer.ownFrame(in: trace)?.display, "loader.py:12 (load)")
        XCTAssertEqual(StackTraceAnalyzer.frames(in: trace).count, 3)
    }

    func testJavaScriptUsesTheFirstOwnFrame() {
        let trace = """
            TypeError: Cannot read properties of undefined (reading 'map')
                at render (/Users/me/web/src/List.jsx:14:22)
                at /Users/me/web/node_modules/react-dom/cjs/react-dom.development.js:1:2
                at Module._compile (node:internal/modules/cjs/loader:1105:14)
            """
        XCTAssertEqual(StackTraceAnalyzer.ownFrame(in: trace)?.display, "List.jsx:14 (render)")
    }

    func testJavaAndGeneric() {
        XCTAssertEqual(StackTraceAnalyzer.ownFrame(in: "    at com.example.app.Main.run(Main.java:42)")?.line, 42)
        XCTAssertEqual(StackTraceAnalyzer.ownFrame(in: "panic: boom\n\t/Users/me/svc/handler.go:88 +0x1d")?.display, "handler.go:88")
        XCTAssertNil(StackTraceAnalyzer.ownFrame(in: "    at Module._compile (node:internal/modules/cjs/loader:1105:14)"))
        XCTAssertNil(StackTraceAnalyzer.ownFrame(in: "no frames here"))
    }
}

final class MyNumberTests: XCTestCase {
    let detector = SensitiveDataDetector()

    func testCheckDigit() {
        XCTAssertTrue(SensitiveDataDetector.myNumberCheckDigitIsValid([1, 2, 3, 4, 5, 6, 7, 8, 9, 0, 1, 8]))
        XCTAssertFalse(SensitiveDataDetector.myNumberCheckDigitIsValid([1, 2, 3, 4, 5, 6, 7, 8, 9, 0, 1, 2]))
    }

    func testDetectsGroupedOrLabelledNumbers() {
        XCTAssertTrue(detector.kinds(in: "1234 5678 9018").contains(.myNumber))
        XCTAssertTrue(detector.kinds(in: "個人番号: 123456789018").contains(.myNumber))
        XCTAssertFalse(detector.kinds(in: "注文番号 123456789018").contains(.myNumber), "a bare 12-digit number needs a keyword")
        XCTAssertFalse(detector.kinds(in: "1234 5678 9012").contains(.myNumber), "wrong check digit")
        XCTAssertFalse(detector.kinds(in: "0000 0000 0000").contains(.myNumber))
        XCTAssertFalse(detector.kinds(in: "4111 1111 1111 111").contains(.myNumber), "part of a longer number")
        XCTAssertTrue(SensitiveKind.myNumber.isHighSeverity)
    }
}

final class DictionaryAndSummaryTests: XCTestCase {
    func testDictionaryFirstSense() {
        XCTAssertEqual(DictionaryDefinition.sanitize("rag | raɡ | noun 1 a piece of old cloth. 2 informal a newspaper.", term: "rag"),
                       "noun a piece of old cloth.")
        XCTAssertEqual(DictionaryDefinition.sanitize("ラグ【rag】ぼろ布。また、敷物。", term: "ラグ"), "ぼろ布。また、敷物。")
        XCTAssertNil(DictionaryDefinition.sanitize("rag", term: "rag"))
        XCTAssertEqual(DictionaryDefinition.sanitize(String(repeating: "word ", count: 80), term: "x")?.count, DictionaryDefinition.maximumLength)
    }

    func testScreenSummarySanitizer() {
        let input = String(repeating: "The council approved the budget. ", count: 10)
        let answer = "1. 予算案が可決された\n- 反対は2票\n• 来月から施行\n・余分な4行目"
        XCTAssertEqual(ScreenSummary.sanitize(answer, input: input), ["予算案が可決された", "反対は2票", "来月から施行"])
        XCTAssertNil(ScreenSummary.sanitize("The council approved the budget.", input: input), "just copies the input")
        XCTAssertTrue(ScreenSummary.prompt(text: String(repeating: "a", count: 5_000), title: "News").hasPrefix("Title: News\nText:\n"))
        XCTAssertLessThanOrEqual(ScreenSummary.prompt(text: String(repeating: "a", count: 5_000), title: nil).count,
                                 ScreenSummary.maximumInputLength + 10)
    }
}
