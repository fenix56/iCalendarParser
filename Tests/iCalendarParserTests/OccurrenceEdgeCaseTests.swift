import XCTest
@testable import iCalendarParser

/// Occurrences of series that need care: long series with `COUNT`, local `UNTIL`, changed values and missing UIDs
final class OccurrenceEdgeCaseTests: XCTestCase {

    private let berlin = TimeZone(identifier: "Europe/Berlin") ?? .current

    private func calendar(_ events: [[String]]) -> ICalendar? {
        var lines: [String] = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Example//EN"]
        for event in events {
            lines += ["BEGIN:VEVENT"] + event + ["END:VEVENT"]
        }
        lines.append("END:VCALENDAR")
        return ICParser().calendar(from: lines.joined(separator: "\r\n"))
    }

    /// A wall-clock time in a time zone
    private func date(_ value: String, _ timeZone: TimeZone) -> Date {
        WallClock(value)?.date(in: timeZone) ?? .distantPast
    }

    private func utc(_ value: String) -> Date {
        WallClock(value)?.date(offset: 0) ?? .distantPast
    }

    // MARK: - COUNT

    func testCountIsKeptWhenPeriodsBeforeWindowAreSkipped() {
        // 3,000,000 minutes from 2020 last until September 2025, more periods than are expanded at once
        let cal = calendar([["UID:1", "DTSTART:20200101T000000Z", "RRULE:FREQ=MINUTELY;COUNT=3000000"]])

        let day = cal?.occurrences(from: utc("20240601T000000"), to: utc("20240602T000000"))
        XCTAssertEqual(day?.count, 1_440)

        let last = utc("20200101T000000").addingTimeInterval(2_999_999 * 60)
        let end = cal?.occurrences(from: last.addingTimeInterval(-120), to: last.addingTimeInterval(3_600))
        XCTAssertEqual(end?.map(\.start), [-120, -60, 0].map { last.addingTimeInterval($0) })
    }

    func testSkippingPeriodsWithCountMatchesExpandingFromStart() {
        let rules = [
            "FREQ=HOURLY;BYMINUTE=0,30;COUNT=500",
            "FREQ=WEEKLY;BYDAY=MO,WE;BYHOUR=9,17;COUNT=300",
            "FREQ=DAILY;BYHOUR=8,12;BYSETPOS=-1;COUNT=200",
            "FREQ=MINUTELY;INTERVAL=7;BYSECOND=0,1;COUNT=5000",
            "FREQ=DAILY;BYMONTH=1,7;COUNT=200"
        ]

        for rule in rules {
            let cal = calendar([["UID:1", "DTSTART:20240101T101500Z", "RRULE:\(rule)"]])
            let all = cal?.occurrences(from: utc("20240101T000000"), to: utc("20300101T000000")).map(\.start) ?? []
            XCTAssertFalse(all.isEmpty, rule)

            // Windows in the middle of the series, around its last occurrence and after it
            for index in [all.count / 2, all.count - 2, all.count - 1] where all.indices.contains(index) {
                let windows = [
                    (all[index], all[index].addingTimeInterval(3_600)),
                    (all[index].addingTimeInterval(1), all[index].addingTimeInterval(86_400 * 30))
                ]
                for (start, end) in windows {
                    let expected = all.filter { $0 >= start && $0 < end }
                    let starts = cal?.occurrences(from: start, to: end).map(\.start)
                    XCTAssertEqual(starts, expected, "\(rule) from \(start)")
                }
            }
        }
    }

    // MARK: - Local time

    func testLocalUntilIsReadInTimeZoneOfStart() {
        // UNTIL should be in UTC here; a local time is read in the time zone of DTSTART, wherever the device is
        let cal = calendar([
            ["UID:1", "DTSTART;TZID=Europe/Berlin:20240101T100000", "RRULE:FREQ=DAILY;UNTIL=20240110T100000"],
            ["UID:2", "DTSTART;TZID=Europe/Berlin:20240101T100000", "RRULE:FREQ=DAILY;UNTIL=20240110T095959"]
        ])

        let range = (date("20240101T000000", berlin), date("20240201T000000", berlin))
        let inclusive = cal?.events[0].occurrences(from: range.0, to: range.1)
        let exclusive = cal?.events[1].occurrences(from: range.0, to: range.1)

        XCTAssertEqual(inclusive?.count, 10)
        XCTAssertEqual(inclusive?.last?.start, date("20240110T100000", berlin))
        XCTAssertEqual(exclusive?.count, 9)
    }

    func testChangedTimeZoneIsUsedForExpansion() throws {
        let cal = calendar([["UID:1", "DTSTART;TZID=UTC:20240325T100000", "RRULE:FREQ=WEEKLY;COUNT=2"]])
        var event = try XCTUnwrap(cal?.events.first)
        var start = try XCTUnwrap(event.dtStart)

        // The same instant, 11:00 in Berlin, which then stays at 11:00 after the switch to summer time
        start.tzId = "Europe/Berlin"
        event.dtStart = start

        let starts = event.occurrences(from: utc("20240301T000000"), to: utc("20240501T000000")).map(\.start)
        XCTAssertEqual(starts, [date("20240325T110000", berlin), date("20240401T110000", berlin)])
    }

    // MARK: - UID

    func testEventsWithoutUIDAreNotOneSeries() {
        let cal = calendar([
            ["SUMMARY:Daily", "DTSTART:20240101T100000Z", "RRULE:FREQ=DAILY;COUNT=3"],
            ["SUMMARY:Moved", "RECURRENCE-ID:20240102T100000Z", "DTSTART:20240102T150000Z"],
            ["SUMMARY:Cancelled", "DTSTART:20240102T120000Z", "STATUS:CANCELLED"]
        ])

        let summaries = cal?.occurrences(from: utc("20240101T000000"), to: utc("20240105T000000")).map(\.event.summary)

        XCTAssertEqual(summaries, ["Daily", "Daily", "Moved", "Daily"])
    }
}
