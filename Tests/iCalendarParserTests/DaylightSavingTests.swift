import XCTest
@testable import iCalendarParser

/// Times skipped when clocks go forward and repeated when they go back.
///
/// A skipped time is read with the offset before the gap, and a repeated time is its first occurrence.
/// See [RFC 5545](https://www.rfc-editor.org/rfc/rfc5545#section-3.3.5).
final class DaylightSavingTests: XCTestCase {

    private func wallClock(_ value: String) -> WallClock {
        guard let wallClock = WallClock(value) else {
            XCTFail("Invalid wall clock value \(value)")
            return WallClock(seconds: 0)
        }
        return wallClock
    }

    private func utc(_ value: String) -> Date {
        wallClock(value).date(offset: 0)
    }

    private func date(_ value: String, _ identifier: String) throws -> Date {
        wallClock(value).date(in: try XCTUnwrap(TimeZone(identifier: identifier)))
    }

    private func zone(_ timeZone: [String]) throws -> DateTimeZone {
        let lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Example//EN"] + timeZone + ["END:VCALENDAR"]
        let calendar = ICParser().calendar(from: lines.joined(separator: "\r\n"))
        return .definition(try XCTUnwrap(calendar?.uniqueTimeZone))
    }

    private func assertResolves(
        _ value: String,
        in identifier: String,
        to expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(try date(value, identifier), utc(expected), "\(identifier) \(value)", file: file, line: line)
    }

    // MARK: - System time zones

    func testSkippedTimeIsReadWithOffsetBeforeGap() throws {
        // The example of RFC 5545: 02:30 is 03:30 EDT
        try assertResolves("20070311T023000", in: "America/New_York", to: "20070311T073000")
        try assertResolves("20240310T023000", in: "America/Los_Angeles", to: "20240310T103000")
        try assertResolves("20240331T023000", in: "Europe/Berlin", to: "20240331T013000")
        try assertResolves("20240929T023000", in: "Pacific/Auckland", to: "20240928T143000")
        // Clocks go forward at midnight, so an all-day event starts at 01:00 on the same day
        try assertResolves("20240908T000000", in: "America/Santiago", to: "20240908T040000")
    }

    func testRepeatedTimeIsFirstOccurrence() throws {
        // The example of RFC 5545: 01:30 is 01:30 EDT
        try assertResolves("20071104T013000", in: "America/New_York", to: "20071104T053000")
        try assertResolves("20241103T013000", in: "America/Los_Angeles", to: "20241103T083000")
        try assertResolves("20241027T023000", in: "Europe/Berlin", to: "20241027T003000")
        try assertResolves("20240407T023000", in: "Pacific/Auckland", to: "20240406T133000")
    }

    // MARK: - VTIMEZONE definitions

    func testSkippedAndRepeatedTimesInDefinition() throws {
        let definition = try zone(TimeZoneFixtures.windowsEurope)

        XCTAssertEqual(definition.date(for: wallClock("20240331T023000")), utc("20240331T013000"))
        XCTAssertEqual(definition.date(for: wallClock("20241027T023000")), utc("20241027T003000"))
        // Both occurrences of 02:30 on 27 October
        XCTAssertEqual(definition.wallClock(for: utc("20241027T003000")), wallClock("20241027T023000"))
        XCTAssertEqual(definition.wallClock(for: utc("20241027T013000")), wallClock("20241027T023000"))
    }

    func testDefinitionsMatchSystemTimeZonesAtEveryQuarterHour() throws {
        let pairs = [
            (TimeZoneFixtures.windowsEurope, "Europe/Berlin"),
            (TimeZoneFixtures.customEastern, "America/New_York")
        ]

        for (definition, identifier) in pairs {
            let definition = try zone(definition)
            let system = DateTimeZone.system(try XCTUnwrap(TimeZone(identifier: identifier)))
            var mismatches = [String]()

            // Every wall-clock time and every instant of 2024, including the skipped and repeated hours
            let first = wallClock("20240101T000000").seconds
            for seconds in stride(from: first, to: first + 366 * WallClock.secondsPerDay, by: 900) {
                let time = WallClock(seconds: seconds)
                if definition.date(for: time) != system.date(for: time) {
                    mismatches.append("date for \(time)")
                }
                if definition.wallClock(for: time.date(offset: 0)) != system.wallClock(for: time.date(offset: 0)) {
                    mismatches.append("wall clock at \(time)")
                }
            }

            XCTAssertEqual(mismatches.prefix(10), [], "\(identifier): \(mismatches.count) mismatches")
        }
    }

    // MARK: - Recurrences

    func testSeriesStartingAtSkippedTimeKeepsItsLocalTime() throws {
        let lines = [
            "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Example//EN",
            "BEGIN:VEVENT", "UID:1", "DTSTART;TZID=Europe/Berlin:20240331T023000", "RRULE:FREQ=DAILY;COUNT=3",
            "END:VEVENT",
            "BEGIN:VEVENT", "UID:2", "DTSTART;TZID=America/Los_Angeles:20240310T023000", "RRULE:FREQ=DAILY;COUNT=3",
            "END:VEVENT",
            "END:VCALENDAR"
        ]
        let events = try XCTUnwrap(ICParser().calendar(from: lines.joined(separator: "\r\n"))?.events)

        let berlin = events[0].occurrences(from: utc("20240301T000000"), to: utc("20240501T000000"))
        let losAngeles = events[1].occurrences(from: utc("20240301T000000"), to: utc("20240501T000000"))

        // 02:30 is skipped on the first day and becomes 03:30; the other days are at 02:30
        XCTAssertEqual(berlin.map(\.start), try ["20240331T033000", "20240401T023000", "20240402T023000"].map {
            try date($0, "Europe/Berlin")
        })
        XCTAssertEqual(losAngeles.map(\.start), try ["20240310T033000", "20240311T023000", "20240312T023000"].map {
            try date($0, "America/Los_Angeles")
        })
    }
}
