import XCTest
@testable import iCalendarParser

/// `ICParser.TimeZoneHandling.legacy` must keep parsing dates the way the
/// parser did before `VTIMEZONE` support, for apps that rely on it.
final class TimeZoneHandlingTests: XCTestCase {

    private let gmtStandardTime = [
        "BEGIN:VTIMEZONE",
        "TZID:GMT Standard Time",
        "BEGIN:STANDARD",
        "DTSTART:16010101T020000",
        "TZOFFSETFROM:+0100",
        "TZOFFSETTO:+0000",
        "RRULE:FREQ=YEARLY;INTERVAL=1;BYDAY=-1SU;BYMONTH=10",
        "END:STANDARD",
        "BEGIN:DAYLIGHT",
        "DTSTART:16010101T010000",
        "TZOFFSETFROM:+0000",
        "TZOFFSETTO:+0100",
        "RRULE:FREQ=YEARLY;INTERVAL=1;BYDAY=-1SU;BYMONTH=3",
        "END:DAYLIGHT",
        "END:VTIMEZONE"
    ]

    private func calendar(
        _ handling: ICParser.TimeZoneHandling,
        event: [String]
    ) -> ICalendar? {
        let lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Example//EN"]
            + gmtStandardTime
            + ["BEGIN:VEVENT", "UID:1"] + event + ["END:VEVENT", "END:VCALENDAR"]
        return ICParser(timeZoneHandling: handling).calendar(from: lines.joined(separator: "\r\n"))
    }

    private func dtStart(_ handling: ICParser.TimeZoneHandling, _ line: String) -> ICDateTime? {
        calendar(handling, event: [line])?.events.first?.dtStart
    }

    private func local(_ value: String) -> Date? {
        WallClock(value)?.date(in: .current)
    }

    private func utc(_ value: String) -> Date? {
        WallClock(value)?.date(offset: 0)
    }

    // MARK: - Default

    func testDefaultIsStandard() {
        XCTAssertEqual(ICParser().timeZoneHandling, .standard)
    }

    // MARK: - Legacy

    func testLegacyReadsValueWithoutTimeZoneAsUTC() {
        let value = dtStart(.legacy, "DTSTART:20240715T100000")

        XCTAssertEqual(value?.date, utc("20240715T100000"))
        XCTAssertEqual(value?.isFloating, true)
    }

    func testLegacyReadsCustomTimeZoneInDeviceTime() {
        let value = dtStart(.legacy, "DTSTART;TZID=GMT Standard Time:20240715T100000")

        XCTAssertEqual(value?.date, local("20240715T100000"))
        XCTAssertEqual(value?.tzId, "GMT Standard Time")
        XCTAssertEqual(value?.isFloating, true)
    }

    func testLegacyReadsVendorPrefixedTimeZoneInDeviceTime() {
        let value = dtStart(.legacy, "DTSTART;TZID=/mozilla.org/20050126_1/Europe/Berlin:20240715T100000")

        XCTAssertEqual(value?.date, local("20240715T100000"))
    }

    func testLegacyDoesNotParseTimeZoneComponents() {
        XCTAssertEqual(calendar(.legacy, event: [])?.timeZones.count, 0)
    }

    func testLegacyKeepsUTCAndSystemTimeZones() {
        XCTAssertEqual(dtStart(.legacy, "DTSTART:20240715T100000Z")?.date, utc("20240715T100000"))
        XCTAssertEqual(
            dtStart(.legacy, "DTSTART;TZID=Europe/London:20240715T100000")?.date,
            utc("20240715T090000")
        )
        XCTAssertEqual(dtStart(.legacy, "DTSTART;VALUE=DATE:20240715")?.date, local("20240715"))
    }

    func testLegacyReadsRecurrenceEndWithoutTimeZoneAsUTC() {
        let rule = calendar(.legacy, event: ["RRULE:FREQ=DAILY;UNTIL=20240720T100000"])?.events.first?.recurrenceRule

        XCTAssertEqual(rule?.until?.date, utc("20240720T100000"))
    }

    func testLegacyReadsOtherDatesWithoutTimeZoneAsUTC() {
        let event = calendar(.legacy, event: ["DTSTAMP:20240101T120000", "CREATED:20240101T120000"])?.events.first

        XCTAssertEqual(event?.dtStamp, utc("20240101T120000"))
        XCTAssertEqual(event?.dtCreated, utc("20240101T120000"))
    }

    // MARK: - Standard, for comparison

    func testStandardReadsValueWithoutTimeZoneAsDeviceTime() {
        XCTAssertEqual(dtStart(.standard, "DTSTART:20240715T100000")?.date, local("20240715T100000"))
    }

    func testStandardResolvesCustomTimeZoneWithDefinition() {
        let value = dtStart(.standard, "DTSTART;TZID=GMT Standard Time:20240715T100000")

        // British Summer Time, UTC+1
        XCTAssertEqual(value?.date, utc("20240715T090000"))
        XCTAssertEqual(value?.isFloating, false)
        XCTAssertEqual(calendar(.standard, event: [])?.timeZones.count, 1)
    }
}
