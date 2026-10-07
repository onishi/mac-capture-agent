import XCTest
@testable import AmbientCore

final class TimeConverterTests: XCTestCase {
    /// 2026-10-07 12:00 UTC = 21:00 JST (a Wednesday).
    let now = Date(timeIntervalSince1970: 1_791_374_400)
    let tokyo = TimeZone(secondsFromGMT: 9 * 3600) ?? .current

    func convert(_ text: String, _ language: String = "ja") -> [String] {
        TimeConverter(now: now, timeZone: tokyo, targetLanguage: language)
            .conversions(in: text)
            .map { "\($0.original) → \($0.converted)" }
    }

    func testZonedTimes() {
        XCTAssertEqual(convert("Launch at 3pm PST"), ["3pm PST → 翌日 8:00（日本時間）"])
        XCTAssertEqual(convert("Standup 10:30 a.m. EST"), ["10:30 a.m. EST → 翌日 0:30（日本時間）"])
        XCTAssertEqual(convert("Deploy at 15:00 UTC", "en"), ["15:00 UTC → 0:00 UTC+9 (+1 day)"])
        XCTAssertEqual(convert("Lunch 12pm GMT"), ["12pm GMT → 21:00（日本時間）"])
    }

    func testIgnoresAmbiguousOrSameZone() {
        XCTAssertTrue(convert("route 3 EST").isEmpty, "a bare number is not a time")
        XCTAssertTrue(convert("9:00 JST").isEmpty, "already the user's zone")
        XCTAssertTrue(convert("13pm PST").isEmpty)
        XCTAssertTrue(convert("the ET phone").isEmpty)
    }

    func testTimestamps() {
        XCTAssertEqual(convert("created_at: 1700000000"), ["1700000000 → 2023-11-15 7:13（日本時間）"])
        XCTAssertEqual(convert("ts=1700000000000 ms"), ["1700000000000 → 2023-11-15 7:13（日本時間）"])
        XCTAssertTrue(convert("id 17000000001").isEmpty, "11 digits is not a timestamp")
        XCTAssertEqual(convert("2026-10-07T15:21:52Z"), ["2026-10-07T15:21:52Z → 2026-10-08 0:21（日本時間）"])
        XCTAssertEqual(convert("2026-10-07T08:00:00-04:00", "en"), ["2026-10-07T08:00:00-04:00 → 2026-10-07 21:00 UTC+9"])
        XCTAssertTrue(convert("2026-10-07T21:00:00+09:00").isEmpty, "same offset")
    }

    func testDatesRelativeToToday() {
        XCTAssertEqual(convert("締切は2026-10-20です"), ["2026-10-20 → 13日後（火）"])
        XCTAssertEqual(convert("10月8日"), ["10月8日 → 明日（木）"])
        XCTAssertEqual(convert("2026年10月7日"), ["2026年10月7日 → 今日（水）"])
        XCTAssertEqual(convert("Due Oct 6", "en"), ["Oct 6 → yesterday (Tue)"])
        XCTAssertEqual(convert("January 5th", "en"), ["January 5th → in 90 days (Tue)"], "no year: the nearest one")
        XCTAssertEqual(convert("2026/9/30", "en"), ["2026/9/30 → 7 days ago (Wed)"])
    }

    func testRejectsImpossibleDatesAndVersions() {
        XCTAssertTrue(convert("2月30日").isEmpty)
        XCTAssertTrue(convert("version 1.2.3").isEmpty)
        XCTAssertTrue(convert("2026-13-01").isEmpty)
    }

    func testCombinedWithUnitsInReadingOrder() {
        let all = QuickConversions.all(in: "72°F at 3pm PST", targetLanguage: "ja", now: now, timeZone: tokyo)
        XCTAssertEqual(all.map(\.original), ["72°F", "3pm PST"])
        let english = QuickConversions.all(in: "72°F at 3pm PST", targetLanguage: "en", now: now, timeZone: tokyo)
        XCTAssertEqual(english.map(\.original), ["3pm PST"], "no unit conversion for English readers, times still")
    }

    func testZoneLabel() {
        XCTAssertEqual(TimeConverter(now: now, timeZone: tokyo, targetLanguage: "ja").zoneLabel, "日本時間")
        XCTAssertEqual(TimeConverter(now: now, timeZone: tokyo, targetLanguage: "en").zoneLabel, "UTC+9")
        XCTAssertEqual(TimeConverter(now: now, timeZone: TimeZone(secondsFromGMT: -(5 * 3600 + 1800)) ?? .current, targetLanguage: "ja").zoneLabel, "UTC-5:30")
    }
}
