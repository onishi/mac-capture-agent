import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#endif
@testable import AmbientCore

final class ErrorDetectorTests: XCTestCase {
    let detector = ErrorDetector()

    /// Representative errors: (log, expected kind, expected line prefix).
    let errors: [(String, String, String)] = [
        ("Traceback (most recent call last):\n  File \"app.py\", line 3, in <module>\n    main()\nKeyError: 'user_id'", "KeyError", "KeyError"),
        ("TypeError: Cannot read properties of undefined (reading 'map')\n    at render (App.js:12:5)", "TypeError", "TypeError"),
        ("Uncaught ReferenceError: foo is not defined", "Uncaught", "Uncaught"),
        ("main.swift:10:5: error: cannot find 'foo' in scope", "error", "main.swift"),
        ("error[E0382]: borrow of moved value: `v`", "error", "error[E0382]"),
        ("npm ERR! code ERESOLVE\nnpm ERR! ERESOLVE unable to resolve dependency tree", "npm ERR!", "npm ERR! code"),
        ("panic: runtime error: index out of range [3] with length 3", "panic", "panic"),
        ("Exception in thread \"main\" java.lang.NullPointerException\n\tat Main.main(Main.java:5)", "NullPointerException", "Exception in thread"),
        ("fatal: not a git repository (or any of the parent directories): .git", "fatal", "fatal:"),
        ("zsh: command not found: pyhton", "command not found", "zsh"),
        ("ModuleNotFoundError: No module named 'requests'", "ModuleNotFoundError", "ModuleNotFoundError"),
        ("Process finished with exit code 1", "exit code", "Process finished")
    ]

    /// Normal output that must not trigger anything.
    let benign: [String] = [
        "Build succeeded\n0 errors, 2 warnings",
        "** BUILD SUCCEEDED **",
        "main.swift:3:7: warning: variable 'x' was never used",
        "Executed 117 tests, with 0 failures (0 unexpected)",
        "✓ 42 passed (1.2s)",
        "added 120 packages in 3s",
        "Compiling AmbientCore ChangeDetector.swift",
        "Error handling is described in the next chapter.",
        "Ran 12 tests in 0.004s\n\nOK (skipped=1)",
        "Process finished with exit code 0"
    ]

    func testDetectsRepresentativeErrors() {
        var detected = 0
        for (log, kind, prefix) in errors {
            guard let error = detector.detect(in: log) else { XCTFail("missed: \(log)"); continue }
            XCTAssertEqual(error.kind, kind, log)
            XCTAssertTrue(error.line.hasPrefix(prefix), "\(error.line) for \(log)")
            detected += 1
        }
        XCTAssertGreaterThanOrEqual(detected, 10)
    }

    func testIgnoresNormalOutput() {
        for log in benign {
            XCTAssertNil(detector.detect(in: log), log)
        }
    }

    func testTracebackPrefersFinalExceptionLine() {
        let log = "Traceback (most recent call last):\n  File \"a.py\", line 1\nValueError: invalid literal for int()"
        XCTAssertEqual(detector.detect(in: log)?.line, "ValueError: invalid literal for int()")
        XCTAssertTrue(detector.detect(in: log)?.context.contains("Traceback") ?? false)
    }

    func testRouterOnlyExplainsErrorsInCodingContexts() {
        let router = AIRouter(detector: ForeignTextDetector(identifier: StubLanguageIdentifier(fallback: LanguageGuess(code: "en", confidence: 0.99)),
                                                            configuration: ForeignTextDetectorConfiguration(userLanguage: "ja", familiarLanguages: ["en"])))
        let region = textRegion("TypeError: Cannot read properties of undefined (reading 'map')")
        let terminal = router.decide(context([region], bundle: "com.apple.Terminal"))
        XCTAssertEqual(terminal.selected.action, .explainError)
        XCTAssertEqual(terminal.selected.context, "TypeError: Cannot read properties of undefined (reading 'map')")
        let browser = router.decide(context([region], bundle: "com.apple.Safari"))
        XCTAssertEqual(browser.selected, .ignore)
        let github = router.decide(AnalysisContext(appName: "Safari", bundleIdentifier: "com.apple.Safari",
                                                  windowTitle: "Fix crash · Pull Request #32 · GitHub", textRegions: [region], visualCategories: []))
        XCTAssertEqual(github.selected.action, .explainError)
    }
}

final class SensitiveDataDetectorTests: XCTestCase {
    let detector = SensitiveDataDetector()

    /// Test fixtures are assembled at runtime so that no complete fake secret
    /// appears in the source (and secret scanners don't flag the repository).
    func fake(_ parts: String...) -> String { parts.joined() }

    func testDetectsSecrets() {
        let samples: [(String, SensitiveKind)] = [
            ("-----BEGIN OPENSSH PRIVATE KEY-----", .privateKey),
            ("aws_access_key_id = " + fake("AKIA", "IOSFODNN7EXAMPLE"), .awsAccessKey),
            ("token: " + fake("ghp_", "abcdefghijklmnopqrstuvwxyz0123456789"), .githubToken),
            ("SLACK=" + fake("xoxb-", "1234567890-abcdefghij"), .slackToken),
            ("key=" + fake("AIza", "SyA1234567890abcdefghijklmnopqrstuv"), .googleAPIKey),
            ("STRIPE_KEY=" + fake("sk_", "live_", "abcdefghijklmnopqrstuvwx"), .stripeKey),
            ("OPENAI_API_KEY=" + fake("sk-", "proj-", "abcdefghijklmnopqrstuvwxyz123456"), .llmAPIKey),
            ("Authorization: Bearer " + fake("eyJ", "hbGciOiJIUzI1NiJ9.", "eyJ", "zdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N"), .jwt),
            ("Card: 4242 4242 4242 4242", .creditCard),
            ("password: hunter2!", .password),
            ("パスワード：abcd1234", .password),
            ("Contact: taro.yamada@example.co.jp", .email),
            ("TEL 03-1234-5678", .phoneNumber),
            ("+81 90-1234-5678", .phoneNumber)
        ]
        for (text, kind) in samples {
            XCTAssertTrue(detector.kinds(in: text).contains(kind), "\(kind) in \(text)")
        }
    }

    func testFalsePositiveRateOnOrdinaryText() {
        let ordinary = [
            "The meeting is at 10:30 on 2026-10-04.",
            "Order #1234567890123 has shipped.",
            "Version 1.2.3 (build 4567) released.",
            "Call the function with sk- prefix to skip.",
            "Enter your password below.",
            "ISBN 978-4-06-512345-6",
            "Tracking number 1234 5678 9012 3456",   // fails Luhn
            "let token = request.headers[\"Authorization\"]",
            "Price: ¥12,800 (tax included)",
            "日時: 2026年10月4日 15:00〜16:30",
            "Commit 3f2a9c1d8e7b6a5f4e3d2c1b0a9f8e7d6c5b4a39",
            "4111 1111 1111 111"   // too short
        ]
        let hits = ordinary.filter { !detector.kinds(in: $0).isEmpty }
        XCTAssertEqual(hits, [], "false positives")
    }

    func testLuhn() {
        XCTAssertTrue(SensitiveDataDetector.luhn([4, 2, 4, 2, 4, 2, 4, 2, 4, 2, 4, 2, 4, 2, 4, 2]))
        XCTAssertFalse(SensitiveDataDetector.luhn([1, 2, 3, 4, 5, 6, 7, 8, 9, 0, 1, 2, 3, 4, 5, 6]))
    }

    func testPartitionExcludesSensitiveRegions() {
        let regions = [textRegion("Bonjour à tous, bienvenue."), textRegion("password: hunter2!", y: 0.5)]
        let (safe, findings) = detector.partition(regions)
        XCTAssertEqual(safe.map(\.text), ["Bonjour à tous, bienvenue."])
        XCTAssertEqual(findings.map(\.kind), [.password])
        XCTAssertEqual(findings.first?.region?.minY, 0.5)
        XCTAssertTrue(SensitiveKind.awsAccessKey.isHighSeverity)
        XCTAssertFalse(SensitiveKind.email.isHighSeverity)
    }
}

final class ScreenShareAndDwellTests: XCTestCase {
    func testScreenShareHeuristics() {
        XCTAssertTrue(ScreenShareHeuristics.isSharing([WindowInfo(ownerName: "Google Chrome", title: "meet.google.com is sharing your screen.")]))
        XCTAssertTrue(ScreenShareHeuristics.isSharing([WindowInfo(ownerName: "CptHost", title: "")]))
        XCTAssertTrue(ScreenShareHeuristics.isSharing([WindowInfo(ownerName: "zoom.us", title: "zoom share toolbar window")]))
        XCTAssertFalse(ScreenShareHeuristics.isSharing([WindowInfo(ownerName: "Safari", title: "How to share your screen in Zoom")]))
        XCTAssertFalse(ScreenShareHeuristics.isSharing([]))
    }

    func testDwellFiresOncePerRest() {
        var tracker = PointerDwellTracker()
        let p = CGPoint(x: 0.5, y: 0.5)
        XCTAssertNil(tracker.update(position: p, at: 0))
        XCTAssertNil(tracker.update(position: CGPoint(x: 0.505, y: 0.5), at: 1))
        XCTAssertEqual(tracker.update(position: p, at: 2.1), p)
        XCTAssertNil(tracker.update(position: p, at: 3), "only once")
        XCTAssertNil(tracker.update(position: CGPoint(x: 0.7, y: 0.5), at: 3.5), "moved: restart")
        XCTAssertNil(tracker.update(position: CGPoint(x: 0.7, y: 0.5), at: 4.5))
        XCTAssertEqual(tracker.update(position: CGPoint(x: 0.7, y: 0.5), at: 5.6), CGPoint(x: 0.7, y: 0.5))
    }

    func testDwellRegionIsClamped() {
        let region = PointerDwellTracker.region(around: CGPoint(x: 0.95, y: 0.02))
        XCTAssertTrue(CGRect.unit.contains(region))
        XCTAssertGreaterThan(region.width, 0.1)
    }

    func testCodingModeByWindowTitle() {
        XCTAssertEqual(AppContextClassifier.classify(bundleIdentifier: "com.google.Chrome", windowTitle: "groue/GRDB.swift: A toolkit · GitHub"), .coding)
        XCTAssertEqual(AppContextClassifier.classify(bundleIdentifier: "com.google.Chrome", windowTitle: "Le Monde"), .general)
        XCTAssertEqual(AppContextClassifier.classify(bundleIdentifier: "com.apple.Terminal"), .coding)
    }
}

final class DeveloperOutputTests: XCTestCase {
    func testSanitizers() {
        XCTAssertNil(DeveloperOutputSanitizer.sanitize(ErrorExplanation(cause: " ", fix: nil), errorLine: "TypeError: x"))
        XCTAssertNil(DeveloperOutputSanitizer.sanitize(ErrorExplanation(cause: "TypeError: x", fix: nil), errorLine: "TypeError: x"))
        let ok = DeveloperOutputSanitizer.sanitize(ErrorExplanation(cause: "「undefined に対して map() を実行」", fix: " "), errorLine: "TypeError: x")
        XCTAssertEqual(ok, ErrorExplanation(cause: "undefined に対して map() を実行", fix: nil))
        XCTAssertNil(DeveloperOutputSanitizer.sanitize(CodeSummary(isCode: false, summary: "text")))
        XCTAssertEqual(DeveloperOutputSanitizer.sanitize(CodeSummary(isCode: true, summary: "API から取得して保存"))?.summary, "API から取得して保存")
    }

    func testLooksLikeCode() {
        XCTAssertTrue(DeveloperOutputSanitizer.looksLikeCode("func load() async throws -> [Item] {\n  let data = try await api.fetch()\n  return decode(data)\n}"))
        XCTAssertFalse(DeveloperOutputSanitizer.looksLikeCode("The quick brown fox jumps over the lazy dog."))
    }
}
