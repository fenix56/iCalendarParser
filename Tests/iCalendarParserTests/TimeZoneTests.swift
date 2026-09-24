import XCTest
@testable import iCalendarParser

final class TimeZoneTests: XCTestCase {

    // MARK: - Fixtures

    /// Outlook / Exchange style definition with a Windows time zone name
    private let windowsEurope = [
        "BEGIN:VTIMEZONE",
        "TZID:W. Europe Standard Time",
        "BEGIN:STANDARD",
        "DTSTART:16010101T030000",
        "TZOFFSETFROM:+0200",
        "TZOFFSETTO:+0100",
        "RRULE:FREQ=YEARLY;INTERVAL=1;BYDAY=-1SU;BYMONTH=10",
        "END:STANDARD",
        "BEGIN:DAYLIGHT",
        "DTSTART:16010101T020000",
        "TZOFFSETFROM:+0100",
        "TZOFFSETTO:+0200",
        "RRULE:FREQ=YEARLY;INTERVAL=1;BYDAY=-1SU;BYMONTH=3",
        "END:DAYLIGHT",
        "END:VTIMEZONE"
    ]

    /// Apple style definition with a custom identifier
    private let customEastern = [
        "BEGIN:VTIMEZONE",
        "TZID:US-Eastern-Custom",
        "BEGIN:DAYLIGHT",
        "TZOFFSETFROM:-0500",
        "RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=2SU",
        "DTSTART:20070311T020000",
        "TZNAME:EDT",
        "TZOFFSETTO:-0400",
        "END:DAYLIGHT",
        "BEGIN:STANDARD",
        "TZOFFSETFROM:-0400",
        "RRULE:FREQ=YEARLY;BYMONTH=11;BYDAY=1SU",
        "DTSTART:20071104T020000",
        "TZNAME:EST",
        "TZOFFSETTO:-0500",
        "END:STANDARD",
        "END:VTIMEZONE"
    ]

    private func calendar(timeZone: [String], event: [String] = []) -> ICalendar? {
        let lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Example//EN"]
            + timeZone
            + (event.isEmpty ? [] : ["BEGIN:VEVENT", "UID:1"] + event + ["END:VEVENT"])
            + ["END:VCALENDAR"]
        return ICParser().calendar(from: lines.joined(separator: "\r\n"))
    }

    private func wallClock(_ value: String) -> WallClock {
        guard let wallClock = WallClock(value) else {
            XCTFail("Invalid wall clock value \(value)")
            return WallClock(seconds: 0)
        }
        return wallClock
    }

    // MARK: - VTIMEZONE parsing

    func testParsesTimeZoneDefinitions() {
        let timeZone = calendar(timeZone: windowsEurope)?.uniqueTimeZone

        XCTAssertEqual(timeZone?.timeZoneId, "W. Europe Standard Time")
        XCTAssertEqual(timeZone?.standard?.timeZoneOffsetTo, "+0100")
        XCTAssertEqual(timeZone?.daylight?.timeZoneOffsetTo, "+0200")
        XCTAssertEqual(timeZone?.standard?.recurrenceRule?.byMonth, [10])
        XCTAssertEqual(timeZone?.daylight?.recurrenceRule?.byDay, [.last(.sunday)])
        // 1601-01-01 03:00 in the +0200 offset in use before the observance
        XCTAssertEqual(timeZone?.standard?.dtStart, wallClock("16010101T030000").date(offset: 7_200))
    }

    func testParsesMultipleTimeZoneDefinitions() {
        let timeZones = calendar(timeZone: windowsEurope + customEastern)?.timeZones

        XCTAssertEqual(timeZones?.map(\.timeZoneId), ["W. Europe Standard Time", "US-Eastern-Custom"])
    }

    // MARK: - TZID resolved with VTIMEZONE

    func testEventTimeWithWindowsTimeZoneName() {
        let event = calendar(
            timeZone: windowsEurope,
            event: [
                "DTSTART;TZID=W. Europe Standard Time:20240115T100000",
                "DTEND;TZID=W. Europe Standard Time:20240715T100000"
            ]
        )?.events.first

        XCTAssertEqual(event?.dtStart?.date, Date(timeIntervalSince1970: 1_705_309_200)) // 2024-01-15 09:00 UTC
        XCTAssertEqual(event?.dtStart?.tzId, "W. Europe Standard Time")
        XCTAssertEqual(event?.dtStart?.isFloating, false)
        XCTAssertEqual(event?.dtEnd?.date, Date(timeIntervalSince1970: 1_721_030_400)) // 2024-07-15 08:00 UTC
    }

    func testWindowsDefinitionMatchesSystemTimeZoneEveryDay() throws {
        let definition = try XCTUnwrap(calendar(timeZone: windowsEurope)?.uniqueTimeZone)
        let berlin = try XCTUnwrap(TimeZone(identifier: "Europe/Berlin"))

        // The EU rules have been in force since 1996
        assertMatches(
            definition,
            berlin,
            from: .init(year: 1996, month: 1, day: 1),
            to: .init(year: 2035, month: 12, day: 31)
        )
    }

    func testCustomDefinitionMatchesSystemTimeZoneEveryDay() throws {
        let definition = try XCTUnwrap(calendar(timeZone: customEastern)?.uniqueTimeZone)
        let newYork = try XCTUnwrap(TimeZone(identifier: "America/New_York"))

        // The US rules have been in force since 2007
        assertMatches(
            definition,
            newYork,
            from: .init(year: 2007, month: 3, day: 12),
            to: .init(year: 2035, month: 12, day: 31)
        )
    }

    func testCustomDefinitionAroundTransitions() throws {
        let definition = try XCTUnwrap(calendar(timeZone: customEastern)?.uniqueTimeZone)

        // 2024-03-10 02:00 EST -> EDT
        XCTAssertEqual(definition.date(for: wallClock("20240310T013000")), Date(timeIntervalSince1970: 1_710_052_200))
        XCTAssertEqual(definition.date(for: wallClock("20240310T033000")), Date(timeIntervalSince1970: 1_710_055_800))
        // 2024-11-03 02:00 EDT -> EST
        XCTAssertEqual(definition.date(for: wallClock("20241102T120000")), Date(timeIntervalSince1970: 1_730_563_200))
        XCTAssertEqual(definition.date(for: wallClock("20241103T120000")), Date(timeIntervalSince1970: 1_730_653_200))
    }

    func testTimeBeforeFirstObservanceUsesOffsetBeforeIt() throws {
        let definition = try XCTUnwrap(calendar(timeZone: customEastern)?.uniqueTimeZone)

        // Before 2007-03-11 02:00 the definition only knows the -0500 offset
        XCTAssertEqual(
            definition.date(for: wallClock("20050101T120000")),
            wallClock("20050101T120000").date(offset: -18_000)
        )
    }

    func testMonthDayRule() {
        // Pre-2007 style "second Sunday" rule
        let observance = ICSubTimeZone(
            dtStart: wallClock("19670312T020000").date(offset: -18_000),
            recurrenceRule: PropertyBuilder.buildRRule(
                from: ("RRULE", "FREQ=YEARLY;BYMONTH=3;BYMONTHDAY=8,9,10,11,12,13,14;BYDAY=SU")
            ),
            timeZoneOffsetFrom: "-0500",
            timeZoneOffsetTo: "-0400"
        )

        XCTAssertEqual(observance.latestOnset(onOrBefore: wallClock("20240601T000000")), wallClock("20240310T020000"))
    }

    func testRuleWithUntilStopsRecurring() {
        let observance = ICSubTimeZone(
            dtStart: wallClock("19870405T020000").date(offset: -18_000),
            recurrenceRule: PropertyBuilder.buildRRule(
                from: ("RRULE", "FREQ=YEARLY;BYMONTH=4;BYDAY=1SU;UNTIL=20060402T070000Z")
            ),
            timeZoneOffsetFrom: "-0500",
            timeZoneOffsetTo: "-0400"
        )

        XCTAssertEqual(observance.latestOnset(onOrBefore: wallClock("20240601T000000")), wallClock("20060402T020000"))
        XCTAssertEqual(observance.latestOnset(onOrBefore: wallClock("19990601T000000")), wallClock("19990404T020000"))
        XCTAssertNil(observance.latestOnset(onOrBefore: wallClock("19870101T000000")))
    }

    // MARK: - TZID resolved without VTIMEZONE

    func testTimeZoneIdWithVendorPrefix() {
        let prefixed = PropertyBuilder.buildDateTime(
            from: ("DTSTART;TZID=/mozilla.org/20050126_1/Europe/Berlin", "20240115T100000")
        )

        XCTAssertEqual(prefixed?.date, Date(timeIntervalSince1970: 1_705_309_200))
        XCTAssertEqual(prefixed?.tzId, "/mozilla.org/20050126_1/Europe/Berlin")
        XCTAssertEqual(prefixed?.isFloating, false)
    }

    func testTimeZoneIdWithMultipleComponents() {
        XCTAssertEqual(
            TimeZoneResolver.timeZone(for: "/citadel.org/20190914_1/America/Argentina/Buenos_Aires")?.identifier,
            "America/Argentina/Buenos_Aires"
        )
        XCTAssertNil(TimeZoneResolver.timeZone(for: "W. Europe Standard Time"))
        XCTAssertNil(TimeZoneResolver.timeZone(for: "Custom/Zone"))
    }

    func testUnknownTimeZoneIdIsFloating() {
        let dateTime = PropertyBuilder.buildDateTime(from: ("DTSTART;TZID=Unknown Zone", "20240115T100000"))

        XCTAssertEqual(dateTime?.tzId, "Unknown Zone")
        XCTAssertEqual(dateTime?.isFloating, true)
        XCTAssertEqual(dateTime?.date, wallClock("20240115T100000").date(in: .current))
    }

    // MARK: - Helpers

    private func assertMatches(
        _ definition: ICTimeZone,
        _ timeZone: TimeZone,
        from start: WallClock.CivilDate,
        to end: WallClock.CivilDate,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let firstDay = WallClock.daysSince1970(year: start.year, month: start.month, day: start.day)
        let lastDay = WallClock.daysSince1970(year: end.year, month: end.month, day: end.day)
        var mismatches = [String]()

        for day in firstDay...lastDay {
            // Noon avoids the ambiguous and skipped hours around transitions
            let noon = WallClock(seconds: day * WallClock.secondsPerDay + 43_200)
            if definition.date(for: noon) != noon.date(in: timeZone) {
                let date = WallClock.civilDate(daysSince1970: day)
                mismatches.append("\(date.year)-\(date.month)-\(date.day)")
            }
        }

        XCTAssertEqual(mismatches.prefix(10), [], "\(mismatches.count) mismatching days", file: file, line: line)
    }
}
