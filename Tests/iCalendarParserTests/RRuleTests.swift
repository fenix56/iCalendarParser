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

    // MARK: - Out-of-range values must not crash

    func testSmallestIntegerIsRejectedWithoutOverflow() {
        let property = ICProperty(
            "RRULE",
            "FREQ=MONTHLY;BYMONTHDAY=-9223372036854775808;BYDAY=-9223372036854775808MO;BYSETPOS=-9223372036854775808"
        )
        let rrule = PropertyBuilder.buildRRule(from: property)

        XCTAssertNil(rrule?.byDayOfMonth)
        XCTAssertNil(rrule?.bySetPos)
        XCTAssertEqual(rrule?.byDay, [.every(.monday)])
        XCTAssertNil(ICRRule.Day(week: .min, dayOfWeek: .monday).week)
    }

    func testNegativeValuesAreValidWithinRange() {
        var rule = ICRRule(byDayOfMonth: [-31, -1, 1, 31], frequency: .monthly)
        XCTAssertEqual(rule.byDayOfMonth, [-31, -1, 1, 31])

        rule.byDayOfMonth = [-32]
        XCTAssertNil(rule.byDayOfMonth)
        rule.byDayOfMonth = [0]
        XCTAssertNil(rule.byDayOfMonth)
        rule.byHour = [-1]
        XCTAssertNil(rule.byHour)

        XCTAssertEqual(ICRRule.Day(week: -53, dayOfWeek: .friday).week, -53)
        XCTAssertNil(ICRRule.Day(week: -54, dayOfWeek: .friday).week)
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
