import XCTest
@testable import iCalendarParser

final class RRuleTests: XCTestCase {
    func testBuildRRule() {
        let property = ICProperty("RRULE", "FREQ=YEARLY;BYMONTH=3;BYDAY=-1SU")
        let rrule = PropertyBuilder.buildRRule(from: property)

        XCTAssertNotNil(rrule)
        XCTAssertEqual(rrule?.frequency, .yearly)
        XCTAssertEqual(rrule?.byMonth, [3])
        XCTAssertEqual(rrule?.byDay, [.init(week: -1, dayOfWeek: .sunday)])
    }

    // MARK: - Day

    func testDayFromValidValues() {
        XCTAssertEqual(ICRRule.Day.from("MO"), .every(.monday))
        XCTAssertEqual(ICRRule.Day.from("1TU"), .first(.tuesday))
        XCTAssertEqual(ICRRule.Day.from("+2WE"), .init(week: 2, dayOfWeek: .wednesday))
        XCTAssertEqual(ICRRule.Day.from("-1SU"), .last(.sunday))
    }

    func testDayFromTooShortValueReturnsNil() {
        XCTAssertNil(ICRRule.Day.from(""))
        XCTAssertNil(ICRRule.Day.from("M"))
    }

    func testDayFromUnknownWeekdayReturnsNil() {
        XCTAssertNil(ICRRule.Day.from("XX"))
    }

    // MARK: - Malformed BYDAY must not crash

    func testBuildRRuleWithEmptyByDay() {
        let property = ICProperty("RRULE", "FREQ=WEEKLY;BYDAY=")
        let rrule = PropertyBuilder.buildRRule(from: property)

        XCTAssertEqual(rrule?.frequency, .weekly)
        XCTAssertEqual(rrule?.byDay, [])
    }

    func testBuildRRuleWithTrailingCommaInByDay() {
        let property = ICProperty("RRULE", "FREQ=WEEKLY;BYDAY=MO,")
        let rrule = PropertyBuilder.buildRRule(from: property)

        XCTAssertEqual(rrule?.byDay, [.every(.monday)])
    }

    func testBuildRRuleWithSingleCharacterByDay() {
        let property = ICProperty("RRULE", "FREQ=WEEKLY;BYDAY=M,TU")
        let rrule = PropertyBuilder.buildRRule(from: property)

        XCTAssertEqual(rrule?.byDay, [.every(.tuesday)])
    }

    func testParseCalendarWithMalformedByDay() {
        let rawIcs = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//Example Inc//Calendar//EN",
            "BEGIN:VEVENT",
            "UID:1",
            "DTSTART:20240101T100000Z",
            "RRULE:FREQ=WEEKLY;BYDAY=MO,,",
            "END:VEVENT",
            "END:VCALENDAR"
        ].joined(separator: "\r\n")

        let calendar = ICParser().calendar(from: rawIcs)

        XCTAssertEqual(calendar?.events.count, 1)
        XCTAssertEqual(calendar?.events.first?.recurrenceRule?.byDay, [.every(.monday)])
    }
}
