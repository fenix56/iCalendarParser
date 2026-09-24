import XCTest
@testable import iCalendarParser

final class ParserTests: XCTestCase {

    // MARK: - Fixtures

    /// Google Calendar style: CRLF, space folding, escaped TEXT, VALARM at the end.
    private let googleInvite = [
        "BEGIN:VCALENDAR",
        "PRODID:-//Google Inc//Google Calendar 70.9054//EN",
        "VERSION:2.0",
        "CALSCALE:GREGORIAN",
        "METHOD:REQUEST",
        "BEGIN:VEVENT",
        "DTSTART:20240115T100000Z",
        "DTEND:20240115T110000Z",
        "DTSTAMP:20240110T090000Z",
        "ORGANIZER;CN=Jane Doe:mailto:jane@example.com",
        "UID:google-event-1@google.com",
        "ATTENDEE;CUTYPE=INDIVIDUAL;ROLE=REQ-PARTICIPANT;PARTSTAT=ACCEPTED;RSVP=TRUE",
        " ;CN=John Smith;X-NUM-GUESTS=0:mailto:john@example.com",
        "DESCRIPTION:Agenda:\\n1. Intro\\n2. Roadmap\\, Q1 goals\\; open questions\\n",
        " \\nJoin: https://meet.example.com/abc-defg-hij",
        "LOCATION:Room 4\\, Building B",
        "SEQUENCE:0",
        "STATUS:CONFIRMED",
        "SUMMARY:Planning\\, Q1",
        "TRANSP:OPAQUE",
        "BEGIN:VALARM",
        "ACTION:DISPLAY",
        "DESCRIPTION:This is an event reminder",
        "TRIGGER:-P0DT0H10M0S",
        "END:VALARM",
        "END:VEVENT",
        "END:VCALENDAR"
    ].joined(separator: "\r\n")

    /// Outlook / Exchange style: tab folding, quoted parameters, uppercase MAILTO,
    /// VALARM before other event properties.
    private let outlookInvite = [
        "BEGIN:VCALENDAR",
        "METHOD:REQUEST",
        "PRODID:Microsoft Exchange Server 2010",
        "VERSION:2.0",
        "BEGIN:VEVENT",
        #"ORGANIZER;CN="Boss, The";SENT-BY="mailto:assistant@example.com":MAILTO:boss@example.com"#,
        #"ATTENDEE;ROLE=REQ-PARTICIPANT;PARTSTAT=NEEDS-ACTION;RSVP=TRUE;CN="Doe, John":MAILTO:jdoe@example.com"#,
        "UID:040000008200E00074C5B7101A82E008",
        "BEGIN:VALARM",
        "DESCRIPTION:REMINDER",
        "TRIGGER;RELATED=START:-PT15M",
        "ACTION:DISPLAY",
        "END:VALARM",
        "SUMMARY;LANGUAGE=en-US:Quarterly review with a very long subject that Outlook",
        "\tfolds with a tab",
        #"DTSTART;TZID="Europe/Berlin":20240115T100000"#,
        #"DTEND;TZID="Europe/Berlin":20240115T110000"#,
        "LOCATION;LANGUAGE=en-US:Main office",
        "DTSTAMP:20240110T090000Z",
        "END:VEVENT",
        "END:VCALENDAR"
    ].joined(separator: "\r\n")

    /// A calendar saved with LF line endings (e.g. exported on Unix or loaded from a file in a repository).
    private let lineFeedCalendar = [
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        "PRODID:-//Apple Inc.//macOS 14.0//EN",
        "BEGIN:VEVENT",
        "UID:apple-1",
        "DTSTART;VALUE=DATE:20240120",
        "SUMMARY:Birthday",
        "END:VEVENT",
        "BEGIN:VEVENT",
        "UID:apple-2",
        "DTSTART:20240121T080000Z",
        "SUMMARY:Breakfast",
        "END:VEVENT",
        "END:VCALENDAR"
    ].joined(separator: "\n")

    // MARK: - Line endings and folding

    func testParsesCalendarWithLineFeedEndings() {
        let calendar = ICParser().calendar(from: lineFeedCalendar)

        XCTAssertNotNil(calendar)
        XCTAssertEqual(calendar?.events.map(\.uid), ["apple-1", "apple-2"])
        XCTAssertEqual(calendar?.events.map(\.summary), ["Birthday", "Breakfast"])
    }

    func testParsesCalendarWithCarriageReturnEndings() {
        let raw = lineFeedCalendar.replacingOccurrences(of: "\n", with: "\r")

        XCTAssertEqual(ICParser().calendar(from: raw)?.events.count, 2)
    }

    func testParsesCalendarWithByteOrderMark() {
        let calendar = ICParser().calendar(from: "\u{FEFF}" + googleInvite)

        XCTAssertEqual(calendar?.events.count, 1)
    }

    func testUnfoldsLinesFoldedWithSpace() {
        let event = ICParser().calendar(from: googleInvite)?.events.first

        XCTAssertEqual(event?.attendees?.count, 1)
        XCTAssertEqual(event?.attendees?.first?.cname, "John Smith")
        XCTAssertEqual(event?.attendees?.first?.email, "john@example.com")
    }

    func testUnfoldsLinesFoldedWithTab() {
        let event = ICParser().calendar(from: outlookInvite)?.events.first

        XCTAssertEqual(
            event?.summary,
            "Quarterly review with a very long subject that Outlookfolds with a tab"
        )
    }

    func testUnfoldsLinesWithLineFeedEndings() {
        let raw = ["SUMMARY:Hello", " World", "\tAgain"].joined(separator: "\n")

        let properties = ICParser().getProperties(from: raw)

        XCTAssertEqual(properties.count, 1)
        XCTAssertEqual(properties.first?.value, "HelloWorldAgain")
    }

    // MARK: - Nested components

    func testPropertiesAfterAlarmBelongToEvent() {
        let event = ICParser().calendar(from: outlookInvite)?.events.first

        XCTAssertNotNil(event?.summary)
        XCTAssertEqual(event?.location, "Main office")
        XCTAssertNotNil(event?.dtStart)
        XCTAssertNotNil(event?.dtEnd)
    }

    func testAlarmPropertiesDoNotLeakIntoEvent() {
        let raw = [
            "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Example//EN",
            "BEGIN:VEVENT",
            "UID:1",
            "BEGIN:VALARM", "ACTION:DISPLAY", "DESCRIPTION:Alarm text", "TRIGGER:-PT5M", "END:VALARM",
            "BEGIN:VALARM", "ACTION:AUDIO", "TRIGGER:-PT1M", "END:VALARM",
            "SUMMARY:Event",
            "END:VEVENT",
            "END:VCALENDAR"
        ].joined(separator: "\r\n")

        let event = ICParser().calendar(from: raw)?.events.first

        XCTAssertEqual(event?.summary, "Event")
        XCTAssertNil(event?.description)
    }

    func testParsesMultipleEventsWithAlarms() {
        let raw = [
            "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Example//EN",
            "BEGIN:VEVENT", "UID:1",
            "BEGIN:VALARM", "TRIGGER:-PT5M", "END:VALARM",
            "SUMMARY:First", "END:VEVENT",
            "BEGIN:VEVENT", "UID:2", "SUMMARY:Second", "END:VEVENT",
            "END:VCALENDAR"
        ].joined(separator: "\r\n")

        let events = ICParser().calendar(from: raw)?.events

        XCTAssertEqual(events?.map(\.summary), ["First", "Second"])
    }

    // MARK: - Quoted parameters

    func testQuotedParameterWithColonDoesNotSplitValue() {
        let event = ICParser().calendar(from: outlookInvite)?.events.first

        XCTAssertEqual(event?.organizer, "MAILTO:boss@example.com")
    }

    func testQuotedParameterValueIsUnquoted() {
        let attendee = ICParser().calendar(from: outlookInvite)?.events.first?.attendees?.first

        XCTAssertEqual(attendee?.cname, "Doe, John")
        XCTAssertEqual(attendee?.participationStatus, .needsAction)
    }

    func testUppercaseMailtoIsRemovedFromAttendeeEmail() {
        let attendee = ICParser().calendar(from: outlookInvite)?.events.first?.attendees?.first

        XCTAssertEqual(attendee?.email, "jdoe@example.com")
    }

    func testQuotedTimeZoneIdMatchesUnquoted() {
        let quoted = ICParser().calendar(from: outlookInvite)?.events.first?.dtStart
        let unquoted = PropertyBuilder.buildDateTime(from: ("DTSTART;TZID=Europe/Berlin", "20240115T100000"))

        XCTAssertEqual(quoted?.tzId, "Europe/Berlin")
        XCTAssertEqual(quoted?.date, unquoted?.date)
        XCTAssertEqual(quoted?.date, Date(timeIntervalSince1970: 1_705_309_200)) // 2024-01-15 09:00 UTC
    }

    func testQuotedSemicolonAndEqualsInParameterValue() {
        let property = ICProperty(#"ATTENDEE;CN="Smith; Jr = CEO";PARTSTAT=ACCEPTED"#, "mailto:ceo@example.com")

        let attendee = PropertyBuilder.buildAttendees(from: [property])?.first

        XCTAssertEqual(attendee?.cname, "Smith; Jr = CEO")
        XCTAssertEqual(attendee?.participationStatus, .accepted)
    }

    // MARK: - TEXT escaping

    func testTextPropertiesAreUnescaped() {
        let event = ICParser().calendar(from: googleInvite)?.events.first

        XCTAssertEqual(event?.summary, "Planning, Q1")
        XCTAssertEqual(event?.location, "Room 4, Building B")
        XCTAssertEqual(
            event?.description,
            "Agenda:\n1. Intro\n2. Roadmap, Q1 goals; open questions\n\nJoin: https://meet.example.com/abc-defg-hij"
        )
    }

    func testUnescapeText() {
        XCTAssertEqual(PropertyBuilder.unescapeText(#"a\nb\Nc"#), "a\nb\nc")
        XCTAssertEqual(PropertyBuilder.unescapeText(#"a\,b\;c"#), "a,b;c")
        XCTAssertEqual(PropertyBuilder.unescapeText(#"C:\\new"#), #"C:\new"#)
        XCTAssertEqual(PropertyBuilder.unescapeText(#"keep \x and trailing \"#), #"keep \x and trailing \"#)
        XCTAssertEqual(PropertyBuilder.unescapeText("plain"), "plain")
    }

    // MARK: - Calendar

    func testParsesGoogleInvite() {
        let calendar = ICParser().calendar(from: googleInvite)
        let event = calendar?.events.first

        XCTAssertEqual(calendar?.method, "REQUEST")
        XCTAssertEqual(calendar?.calendarScale, "GREGORIAN")
        XCTAssertEqual(calendar?.events.count, 1)
        XCTAssertEqual(event?.uid, "google-event-1@google.com")
        XCTAssertEqual(event?.status, "CONFIRMED")
        XCTAssertEqual(event?.sequence, 0)
        XCTAssertEqual(event?.dtStart?.date, Date(timeIntervalSince1970: 1_705_312_800)) // 2024-01-15 10:00 UTC
    }

    // MARK: - Quote-aware split

    func testSplitOutsideQuotes() {
        XCTAssertEqual(#"A;B="x;y";C"#.splitOutsideQuotes(separator: ";"), ["A", #"B="x;y""#, "C"])
        XCTAssertEqual(#"N;P="a:b":v:w"#.splitOutsideQuotes(separator: ":", maxSplits: 1), [#"N;P="a:b""#, "v:w"])
        XCTAssertEqual("".splitOutsideQuotes(separator: ";"), [""])
    }
}
