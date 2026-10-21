import XCTest
@testable import iCalendarParser

final class OccurrenceTests: XCTestCase {

    private let berlin = TimeZone(identifier: "Europe/Berlin") ?? .current

    private func calendar(
        _ events: [[String]],
        timeZones: [String] = [],
        handling: ICParser.TimeZoneHandling = .standard
    ) -> ICalendar? {
        var lines: [String] = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Example//EN"]
        lines += timeZones
        for event in events {
            lines += ["BEGIN:VEVENT"] + event + ["END:VEVENT"]
        }
        lines.append("END:VCALENDAR")
        return ICParser(timeZoneHandling: handling).calendar(from: lines.joined(separator: "\r\n"))
    }

    /// A wall-clock time in a time zone
    private func date(_ value: String, _ timeZone: TimeZone) -> Date {
        WallClock(value)?.date(in: timeZone) ?? .distantPast
    }

    private func utc(_ value: String) -> Date {
        WallClock(value)?.date(offset: 0) ?? .distantPast
    }

    // MARK: - Expansion

    func testWeeklyEventInDayAndWeekWindows() {
        let cal = calendar([[
            "UID:standup", "SUMMARY:Stand-up",
            "DTSTART;TZID=Europe/Berlin:20240101T093000",
            "DTEND;TZID=Europe/Berlin:20240101T094500",
            "RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR"
        ]])

        let day = cal?.occurrences(from: date("20240515T000000", berlin), to: date("20240516T000000", berlin))
        XCTAssertEqual(day?.map(\.start), [date("20240515T093000", berlin)])
        XCTAssertEqual(day?.first?.end, date("20240515T094500", berlin))
        XCTAssertEqual(day?.first?.event.summary, "Stand-up")

        let week = cal?.occurrences(from: date("20240513T000000", berlin), to: date("20240520T000000", berlin))
        XCTAssertEqual(week?.count, 3)
    }

    func testMonthlyOrdinalWeekday() {
        let cal = calendar([["UID:1", "DTSTART:20240109T100000Z", "RRULE:FREQ=MONTHLY;BYDAY=2TU"]])

        let starts = cal?.occurrences(from: utc("20240101T000000"), to: utc("20240601T000000")).map(\.start)

        XCTAssertEqual(starts, ["20240109", "20240213", "20240312", "20240409", "20240514"].map {
            utc($0 + "T100000")
        })
    }

    func testLocalTimeIsKeptAcrossDaylightSavingTransition() {
        let cal = calendar([["UID:1", "DTSTART;TZID=Europe/Berlin:20240325T100000", "RRULE:FREQ=WEEKLY"]])

        let starts = cal?.occurrences(from: utc("20240320T000000"), to: utc("20240405T000000")).map(\.start)

        // 10:00 CET (UTC+1), then 10:00 CEST (UTC+2) after the switch on 31 March
        XCTAssertEqual(starts, [Date(timeIntervalSince1970: 1_711_357_200), Date(timeIntervalSince1970: 1_711_958_400)])
    }

    func testLocalTimeIsKeptWithTimeZoneDefinition() {
        let windowsEurope = [
            "BEGIN:VTIMEZONE", "TZID:W. Europe Standard Time",
            "BEGIN:STANDARD", "DTSTART:16010101T030000", "TZOFFSETFROM:+0200", "TZOFFSETTO:+0100",
            "RRULE:FREQ=YEARLY;BYDAY=-1SU;BYMONTH=10", "END:STANDARD",
            "BEGIN:DAYLIGHT", "DTSTART:16010101T020000", "TZOFFSETFROM:+0100", "TZOFFSETTO:+0200",
            "RRULE:FREQ=YEARLY;BYDAY=-1SU;BYMONTH=3", "END:DAYLIGHT",
            "END:VTIMEZONE"
        ]
        let cal = calendar(
            [["UID:1", "DTSTART;TZID=W. Europe Standard Time:20240325T100000", "RRULE:FREQ=WEEKLY;COUNT=2"]],
            timeZones: windowsEurope
        )

        let starts = cal?.occurrences(from: utc("20240320T000000"), to: utc("20240405T000000")).map(\.start)

        XCTAssertEqual(starts, [Date(timeIntervalSince1970: 1_711_357_200), Date(timeIntervalSince1970: 1_711_958_400)])
    }

    func testCountIncludesOccurrencesBeforeWindow() {
        let cal = calendar([["UID:1", "DTSTART:20240101T100000Z", "RRULE:FREQ=DAILY;COUNT=5"]])

        let starts = cal?.occurrences(from: utc("20240104T000000"), to: utc("20240201T000000")).map(\.start)

        XCTAssertEqual(starts, [utc("20240104T100000"), utc("20240105T100000")])
    }

    func testAllDayUntilIsInclusive() {
        let cal = calendar([["UID:1", "DTSTART;VALUE=DATE:20240101", "RRULE:FREQ=DAILY;UNTIL=20240103"]])

        let occurrences = cal?.occurrences(
            from: date("20231201T000000", .current),
            to: date("20240201T000000", .current)
        )

        XCTAssertEqual(occurrences?.count, 3)
        XCTAssertEqual(occurrences?.allSatisfy(\.isAllDay), true)
    }

    func testRecurrenceDatesAreAdded() {
        let cal = calendar([[
            "UID:1", "DTSTART:20240101T100000Z", "RRULE:FREQ=WEEKLY;COUNT=2",
            "RDATE:20240103T150000Z,20240108T100000Z",
            "RDATE;VALUE=PERIOD:20240105T120000Z/PT1H"
        ]])

        let starts = cal?.occurrences(from: utc("20240101T000000"), to: utc("20240201T000000")).map(\.start)

        // 2024-01-08 10:00 is both a rule occurrence and an RDATE, and appears once
        XCTAssertEqual(starts, [
            utc("20240101T100000"), utc("20240103T150000"), utc("20240105T120000"), utc("20240108T100000")
        ])
    }

    // MARK: - EXDATE

    func testExceptionDatesAreSkipped() {
        let cal = calendar([[
            "UID:1",
            "DTSTART;TZID=Europe/Berlin:20240101T100000",
            "RRULE:FREQ=DAILY;COUNT=6",
            "EXDATE;TZID=Europe/Berlin:20240102T100000,20240104T100000",
            "EXDATE:20240105T090000Z"
        ]])

        let starts = cal?.occurrences(from: utc("20240101T000000"), to: utc("20240201T000000")).map(\.start)

        XCTAssertEqual(cal?.events.first?.exceptionDates.count, 3)
        XCTAssertEqual(starts, ["20240101T100000", "20240103T100000", "20240106T100000"].map { date($0, berlin) })
    }

    func testExceptionDateAsDateForAllDayAndTimedEvents() {
        let cal = calendar([
            ["UID:all-day", "DTSTART;VALUE=DATE:20240101", "RRULE:FREQ=DAILY;COUNT=3", "EXDATE;VALUE=DATE:20240102"],
            ["UID:timed", "DTSTART:20240101T100000Z", "RRULE:FREQ=DAILY;COUNT=3", "EXDATE;VALUE=DATE:20240102"]
        ])

        let occurrences = cal?.occurrences(from: utc("20231231T000000"), to: utc("20240110T000000")) ?? []

        XCTAssertEqual(occurrences.filter { $0.event.uid == "all-day" }.count, 2)
        XCTAssertEqual(occurrences.filter { $0.event.uid == "timed" }.map(\.start), [
            utc("20240101T100000"), utc("20240103T100000")
        ])
    }

    // MARK: - RECURRENCE-ID

    private let movedSeries = [
        [
            "UID:series", "SUMMARY:Weekly",
            "DTSTART;TZID=Europe/Berlin:20240101T100000", "DTEND;TZID=Europe/Berlin:20240101T110000",
            "RRULE:FREQ=WEEKLY;COUNT=4"
        ],
        [
            "UID:series", "SUMMARY:Weekly (moved)",
            "RECURRENCE-ID;TZID=Europe/Berlin:20240108T100000",
            "DTSTART;TZID=Europe/Berlin:20240109T150000", "DTEND;TZID=Europe/Berlin:20240109T160000"
        ]
    ]

    func testMovedOccurrenceReplacesOriginal() {
        let occurrences = calendar(movedSeries)?.occurrences(
            from: date("20240101T000000", berlin),
            to: date("20240201T000000", berlin)
        ) ?? []

        XCTAssertEqual(occurrences.map(\.start), [
            date("20240101T100000", berlin), date("20240109T150000", berlin),
            date("20240115T100000", berlin), date("20240122T100000", berlin)
        ])
        XCTAssertEqual(occurrences[1].event.summary, "Weekly (moved)")
        XCTAssertEqual(occurrences[1].end, date("20240109T160000", berlin))
        XCTAssertEqual(occurrences[1].originalStart, date("20240108T100000", berlin))
        XCTAssertEqual(occurrences[2].originalStart, occurrences[2].start)
    }

    func testMovedOccurrenceIsFoundByItsNewDate() {
        // A window that contains only the new date
        let occurrences = calendar(movedSeries)?.occurrences(
            from: date("20240109T000000", berlin),
            to: date("20240110T000000", berlin)
        )

        XCTAssertEqual(occurrences?.map(\.event.summary), ["Weekly (moved)"])
    }

    func testMovedOccurrenceIsGoneFromItsOriginalDate() {
        // A window that contains only the original date
        let occurrences = calendar(movedSeries)?.occurrences(
            from: date("20240108T000000", berlin),
            to: date("20240109T000000", berlin)
        )

        XCTAssertEqual(occurrences?.count, 0)
    }

    // MARK: - Cancelled

    func testCancelledOccurrenceAndSeries() {
        let cal = calendar([
            ["UID:series", "DTSTART:20240101T100000Z", "RRULE:FREQ=DAILY;COUNT=3"],
            ["UID:series", "RECURRENCE-ID:20240102T100000Z", "DTSTART:20240102T100000Z", "STATUS:CANCELLED"],
            ["UID:cancelled", "DTSTART:20240101T120000Z", "RRULE:FREQ=DAILY;COUNT=3", "STATUS:CANCELLED"],
            ["UID:cancelled", "RECURRENCE-ID:20240102T120000Z", "DTSTART:20240102T130000Z"]
        ])
        let rangeStart = utc("20240101T000000")
        let rangeEnd = utc("20240110T000000")

        XCTAssertEqual(
            cal?.occurrences(from: rangeStart, to: rangeEnd).map(\.start),
            [utc("20240101T100000"), utc("20240103T100000")]
        )
        XCTAssertEqual(cal?.occurrences(from: rangeStart, to: rangeEnd, includeCancelled: true).count, 6)
    }

    // MARK: - End times

    func testEndFromDuration() {
        let cal = calendar([
            ["UID:timed", "DTSTART:20240101T100000Z", "DURATION:PT1H30M"],
            ["UID:days", "DTSTART;TZID=Europe/Berlin:20240330T100000", "DURATION:P1D"]
        ])

        let occurrences = cal?.occurrences(from: utc("20240101T000000"), to: utc("20240401T000000")) ?? []

        XCTAssertEqual(occurrences.first?.end, utc("20240101T113000"))
        // A nominal day across the switch to summer time is 23 hours
        XCTAssertEqual(occurrences.last?.end, date("20240331T100000", berlin))
    }

    func testAllDayEnds() {
        let cal = calendar([
            ["UID:one", "DTSTART;VALUE=DATE:20240101"],
            ["UID:three", "DTSTART;VALUE=DATE:20240105", "DTEND;VALUE=DATE:20240108"]
        ])

        let occurrences = cal?.occurrences(
            from: date("20240101T000000", .current),
            to: date("20240201T000000", .current)
        )

        XCTAssertEqual(occurrences?.first?.end, date("20240102T000000", .current))
        XCTAssertEqual(occurrences?.last?.end, date("20240108T000000", .current))
    }

    func testOccurrenceInProgressAtWindowStartIsIncluded() {
        let cal = calendar([["UID:1", "DTSTART:20240101T230000Z", "DTEND:20240102T010000Z", "RRULE:FREQ=DAILY"]])

        let starts = cal?.occurrences(from: utc("20240105T000000"), to: utc("20240105T120000")).map(\.start)

        XCTAssertEqual(starts, [utc("20240104T230000")])
    }

    // MARK: - Legacy

    func testLegacyExpandsTimesWithoutTimeZoneInUTC() {
        let cal = calendar(
            [["UID:1", "DTSTART:20240318T100000", "RRULE:FREQ=WEEKLY;COUNT=2", "EXDATE:20240325T100000"]],
            handling: .legacy
        )

        let starts = cal?.occurrences(from: utc("20240301T000000"), to: utc("20240401T000000")).map(\.start)

        XCTAssertEqual(starts, [utc("20240318T100000")])
    }

    // MARK: - Sorting and ranges

    func testOccurrencesOfAllEventsAreSorted() {
        let cal = calendar([
            ["UID:b", "DTSTART:20240101T120000Z", "RRULE:FREQ=DAILY;COUNT=2"],
            ["UID:a", "DTSTART:20240101T080000Z", "RRULE:FREQ=DAILY;COUNT=2"]
        ])

        let uids = cal?.occurrences(from: utc("20240101T000000"), to: utc("20240103T000000")).map(\.event.uid)

        XCTAssertEqual(uids, ["a", "b", "a", "b"])
    }

    func testEmptyRangeAndEventWithoutStart() {
        let cal = calendar([["UID:1", "SUMMARY:No start"], ["UID:2", "DTSTART:20240101T100000Z"]])

        XCTAssertEqual(cal?.occurrences(from: utc("20240102T000000"), to: utc("20240101T000000")).count, 0)
        XCTAssertEqual(cal?.occurrences(from: utc("20240101T000000"), to: utc("20240102T000000")).count, 1)
    }

    func testLongRunningSeriesIsExpandedFromWindow() {
        let cal = calendar([["UID:1", "DTSTART:19700101T100000Z", "RRULE:FREQ=MINUTELY;INTERVAL=5"]])

        let starts = cal?.occurrences(from: utc("20240101T100000"), to: utc("20240101T102000")).map(\.start)

        XCTAssertEqual(starts?.count, 4)
    }

    // MARK: - DURATION

    func testDurationParsing() {
        XCTAssertEqual(ICDuration("PT1H30M"), ICDuration(hours: 1, minutes: 30))
        XCTAssertEqual(ICDuration("P15DT5H0M20S"), ICDuration(days: 15, hours: 5, seconds: 20))
        XCTAssertEqual(ICDuration("P7W"), ICDuration(weeks: 7))
        XCTAssertEqual(ICDuration("-PT15M"), ICDuration(isNegative: true, minutes: 15))
        XCTAssertEqual(ICDuration("+P1D")?.timeInterval, 86_400)
        XCTAssertEqual(ICDuration("-PT15M")?.exactSeconds, -900)

        for invalid in ["", "P", "PT", "1H", "P1H", "PT1D", "P1DT", "PT1H1H", "P-1D", "PTXM"] {
            XCTAssertNil(ICDuration(invalid), invalid)
        }
    }
}
