import XCTest
@testable import iCalendarParser

final class DateTimeParsingTests: XCTestCase {

    private func dateTime(_ name: String, _ value: String) -> ICDateTime? {
        PropertyBuilder.buildDateTime(from: (name: name, value: value))
    }

    private func localDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))
    }

    // MARK: - DATE-TIME forms

    func testUTCDateTime() {
        let value = dateTime("DTSTART", "20240115T100000Z")

        XCTAssertEqual(value?.date, Date(timeIntervalSince1970: 1_705_312_800))
        XCTAssertEqual(value?.type, .dateTime)
        XCTAssertNil(value?.tzId)
        XCTAssertEqual(value?.isFloating, false)
    }

    func testDateTimeWithTimeZoneId() {
        let value = dateTime("DTSTART;TZID=Europe/Berlin", "20240115T100000")

        XCTAssertEqual(value?.date, Date(timeIntervalSince1970: 1_705_309_200))
        XCTAssertEqual(value?.tzId, "Europe/Berlin")
        XCTAssertEqual(value?.isFloating, false)
    }

    func testFloatingDateTimeIsLocalTime() {
        let value = dateTime("DTSTART", "20240101T100000")

        XCTAssertEqual(value?.date, localDate(2024, 1, 1, 10))
        XCTAssertEqual(value?.type, .dateTime)
        XCTAssertNil(value?.tzId)
        XCTAssertEqual(value?.isFloating, true)
    }

    func testTimeSkippedByDaylightSavingMovesForward() {
        // 2024-03-31 02:30 does not exist in Berlin; it resolves to 03:30 CEST
        let value = dateTime("DTSTART;TZID=Europe/Berlin", "20240331T023000")

        XCTAssertEqual(value?.date, Date(timeIntervalSince1970: 1_711_848_600)) // 01:30 UTC
    }

    // MARK: - DATE

    func testDateWithValueParameter() {
        let value = dateTime("DTSTART;VALUE=DATE", "20240120")

        XCTAssertEqual(value?.type, .date)
        XCTAssertEqual(value?.date, localDate(2024, 1, 20))
    }

    func testDateIsInferredWithoutValueParameter() {
        let value = dateTime("DTSTART", "20240120")

        XCTAssertEqual(value?.type, .date)
        XCTAssertEqual(value?.date, localDate(2024, 1, 20))
    }

    // MARK: - UNTIL

    func testUntilAsDate() {
        let rule = PropertyBuilder.buildRRule(from: ("RRULE", "FREQ=DAILY;UNTIL=20240110"))

        XCTAssertEqual(rule?.until?.type, .date)
        XCTAssertEqual(rule?.until?.date, localDate(2024, 1, 10))
        XCTAssertNil(rule?.count)
    }

    func testUntilAsUTCDateTime() {
        let rule = PropertyBuilder.buildRRule(from: ("RRULE", "FREQ=WEEKLY;UNTIL=20240110T235959Z"))

        XCTAssertEqual(rule?.until?.type, .dateTime)
        XCTAssertEqual(rule?.until?.date, Date(timeIntervalSince1970: 1_704_931_199))
    }

    func testAllDayEventWithUntilIsBounded() {
        let raw = [
            "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Example//EN",
            "BEGIN:VEVENT", "UID:1",
            "DTSTART;VALUE=DATE:20240101",
            "RRULE:FREQ=DAILY;UNTIL=20240110",
            "END:VEVENT", "END:VCALENDAR"
        ].joined(separator: "\r\n")

        let rule = ICParser().calendar(from: raw)?.events.first?.recurrenceRule

        XCTAssertNotNil(rule?.until)
    }

    // MARK: - Validation

    func testInvalidValuesAreRejected() {
        let invalid = [
            "", "2024011", "202401150", "20241301", "20240001", "20240230", "20230229",
            "20240101T250000", "20240101T106000", "20240101T100061", "2024010aT100000",
            "20240101X100000", "20240101T1000", "20240101T100000ZZ", "abcdefgh"
        ]

        for value in invalid {
            XCTAssertNil(dateTime("DTSTART", value), value)
        }
    }

    func testLeapDayAndLeapSecond() {
        XCTAssertNotNil(dateTime("DTSTART", "20240229"))
        XCTAssertEqual(
            dateTime("DTSTART", "20161231T235960Z")?.date,
            dateTime("DTSTART", "20161231T235959Z")?.date
        )
    }

    func testDateTimeBefore1970() {
        XCTAssertEqual(dateTime("DTSTART", "19691231T235959Z")?.date, Date(timeIntervalSince1970: -1))
        XCTAssertEqual(dateTime("DTSTART", "16010101T000000Z")?.date, Date(timeIntervalSince1970: -11_644_473_600))
    }

    // MARK: - Calendar arithmetic

    func testWeekday() {
        XCTAssertEqual(WallClock(year: 1970, month: 1, day: 1).weekday, 5) // Thursday
        XCTAssertEqual(WallClock(year: 1969, month: 12, day: 31).weekday, 4) // Wednesday
        XCTAssertEqual(WallClock(year: 2024, month: 1, day: 15).weekday, 2) // Monday
        XCTAssertEqual(WallClock(year: 1601, month: 1, day: 1).weekday, 2) // Monday
    }

    func testCivilDateRoundTrip() {
        for days in stride(from: -800_000, through: 800_000, by: 37) {
            let date = WallClock.civilDate(daysSince1970: days)
            XCTAssertEqual(WallClock.daysSince1970(year: date.year, month: date.month, day: date.day), days)
        }
    }

    func testComponentsBefore1970() {
        let wallClock = WallClock(year: 1969, month: 12, day: 31, secondsOfDay: 3_600)

        XCTAssertEqual(wallClock.year, 1969)
        XCTAssertEqual(wallClock.day, 31)
        XCTAssertEqual(wallClock.secondsOfDay, 3_600)
    }

    func testUTCOffset() {
        XCTAssertEqual(UTCOffset.seconds(from: "+0100"), 3_600)
        XCTAssertEqual(UTCOffset.seconds(from: "-0500"), -18_000)
        XCTAssertEqual(UTCOffset.seconds(from: "+053000"), 19_800)
        XCTAssertEqual(UTCOffset.seconds(from: "-0000"), 0)
        XCTAssertNil(UTCOffset.seconds(from: "0100"))
        XCTAssertNil(UTCOffset.seconds(from: "+01"))
        XCTAssertNil(UTCOffset.seconds(from: "+0160"))
        XCTAssertNil(UTCOffset.seconds(from: "+01a0"))
    }
}
