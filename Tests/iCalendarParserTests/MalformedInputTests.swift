import XCTest
@testable import iCalendarParser

/// Values from an untrusted feed that are valid in form but far out of any sensible range
final class MalformedInputTests: XCTestCase {

    private func calendar(_ event: [String]) -> ICalendar? {
        let lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Example//EN", "BEGIN:VEVENT", "UID:1"]
            + event
            + ["END:VEVENT", "END:VCALENDAR"]
        return ICParser().calendar(from: lines.joined(separator: "\r\n"))
    }

    private func utc(_ value: String) -> Date {
        WallClock(value)?.date(offset: 0) ?? .distantPast
    }

    // MARK: - RRULE

    func testOutOfRangeRulePartsDoNotCrash() {
        let cal = calendar([
            "DTSTART:20240101T100000Z",
            "RRULE:FREQ=MONTHLY;BYMONTHDAY=-9223372036854775808;BYDAY=-9223372036854775808MO"
        ])

        let starts = cal?.occurrences(from: utc("20240101T000000"), to: utc("20240201T000000")).map(\.start)

        // BYMONTHDAY is invalid and dropped; BYDAY=MO without its invalid ordinal remains
        XCTAssertEqual(starts?.first, utc("20240101T100000"))
        XCTAssertEqual(starts?.count, 5)
    }

    func testHugeIntervalRepeatsOnlyOutsideAnyRange() {
        for frequency in ["SECONDLY", "MINUTELY", "HOURLY", "DAILY", "WEEKLY", "MONTHLY", "YEARLY"] {
            for count in ["", ";COUNT=3"] {
                let cal = calendar([
                    "DTSTART:20240101T100000Z",
                    "RRULE:FREQ=\(frequency);INTERVAL=1000000000000000\(count)"
                ])

                let starts = cal?.occurrences(from: utc("20231201T000000"), to: utc("20991231T000000")).map(\.start)

                XCTAssertEqual(starts, [utc("20240101T100000")], "\(frequency)\(count)")
            }
        }
    }

    func testLongIntervalStillRepeats() {
        let cal = calendar(["DTSTART:00010101T000000Z", "RRULE:FREQ=YEARLY;INTERVAL=4000;COUNT=3"])

        let starts = cal?.occurrences(from: utc("00010101T000000"), to: utc("99991231T000000")).map(\.start)

        XCTAssertEqual(starts, [utc("00010101T000000"), utc("40010101T000000"), utc("80010101T000000")])
    }

    // MARK: - DURATION

    func testHugeDurationIsRejected() {
        XCTAssertNil(ICDuration("P99999999999999W"))
        XCTAssertNil(ICDuration("PT99999999999999999H"))
        XCTAssertNil(ICDuration("P2000000000000000000W"))
        XCTAssertEqual(ICDuration("P999999999D")?.days, 999_999_999)
        XCTAssertEqual(ICDuration("P52W")?.weeks, 52)
    }

    func testEventWithHugeDurationDoesNotCrash() {
        for duration in ["P99999999999999W", "PT99999999999999999H", "P2000000000000000000W"] {
            let cal = calendar(["DTSTART:20240101T100000Z", "DURATION:\(duration)", "RRULE:FREQ=DAILY"])

            let occurrences = cal?.occurrences(from: utc("20240105T000000"), to: utc("20240106T000000"))

            XCTAssertNil(cal?.events.first?.duration, duration)
            XCTAssertEqual(occurrences?.map(\.start), [utc("20240105T100000")], duration)
        }
    }

    func testLongestDurationDoesNotCrash() {
        let cal = calendar([
            "DTSTART:20240101T100000Z",
            "DURATION:P999999999W999999999DT999999999H999999999M999999999S",
            "RRULE:FREQ=WEEKLY;COUNT=2"
        ])

        let occurrences = cal?.occurrences(from: utc("20240201T000000"), to: utc("20240202T000000"))

        // Both occurrences last for millions of years, so both are in progress
        XCTAssertEqual(occurrences?.map(\.start), [utc("20240101T100000"), utc("20240108T100000")])
    }
}
