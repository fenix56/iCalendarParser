import XCTest
@testable import iCalendarParser

final class PropertyDetailsTests: XCTestCase {

    private func calendar(_ lines: [String], header: [String] = ["VERSION:2.0"]) -> ICalendar? {
        let raw = ["BEGIN:VCALENDAR", "PRODID:-//Example//EN"] + header + lines + ["END:VCALENDAR"]
        return ICParser().calendar(from: raw.joined(separator: "\r\n"))
    }

    private func event(_ lines: [String]) -> ICEvent? {
        calendar(["BEGIN:VEVENT", "UID:1"] + lines + ["END:VEVENT"])?.events.first
    }

    // MARK: - Case-insensitive names and values

    func testNamesAndEnumeratedValuesAreCaseInsensitive() {
        let parsed = calendar([
            "begin:vevent",
            "uid:lower",
            "summary:Lower case",
            "dtstart;tzid=Europe/Berlin:20240115t100000",
            "dtend;value=date:20240116",
            "rrule:freq=weekly;byday=mo,we;wkst=su;until=20240131t000000z",
            "attendee;cn=Jane;partstat=accepted;role=chair:MAILTO:jane@example.com",
            "end:vevent"
        ])
        let lowercase = parsed?.events.first

        XCTAssertEqual(parsed?.events.count, 1)
        XCTAssertEqual(lowercase?.summary, "Lower case")
        XCTAssertEqual(lowercase?.dtStart?.tzId, "Europe/Berlin")
        XCTAssertEqual(lowercase?.dtStart?.date, Date(timeIntervalSince1970: 1_705_309_200))
        XCTAssertEqual(lowercase?.dtEnd?.type, .date)
        XCTAssertEqual(lowercase?.recurrenceRule?.frequency, .weekly)
        XCTAssertEqual(lowercase?.recurrenceRule?.byDay, [.every(.monday), .every(.wednesday)])
        XCTAssertEqual(lowercase?.recurrenceRule?.startOfWorkweek, .sunday)
        XCTAssertNotNil(lowercase?.recurrenceRule?.until)
        XCTAssertEqual(lowercase?.attendees?.first?.cname, "Jane")
        XCTAssertEqual(lowercase?.attendees?.first?.participationStatus, .accepted)
        XCTAssertEqual(lowercase?.attendees?.first?.role, "CHAIR")
    }

    func testParameterValuesKeepTheirCase() {
        let attendee = event(["ATTENDEE;CN=Jane de Vries:mailto:jane@example.com"])?.attendees?.first

        XCTAssertEqual(attendee?.cname, "Jane de Vries")
    }

    func testPropertyNameMustMatchExactly() {
        let parsed = event(["SUMMARYX:Wrong", "SUMMARY:Right"])

        XCTAssertEqual(parsed?.summary, "Right")
    }

    // MARK: - Non-standard properties

    func testNonStandardPropertiesAreKeyedByNameWithoutParameters() {
        let parsed = event([
            "X-ALT-DESC;FMTTYPE=text/html:<b>Agenda</b>",
            "x-microsoft-cdo-busystatus:BUSY"
        ])

        XCTAssertEqual(parsed?.nonStandardProperties?["X-ALT-DESC"], "<b>Agenda</b>")
        XCTAssertEqual(parsed?.nonStandardProperties?["X-MICROSOFT-CDO-BUSYSTATUS"], "BUSY")
    }

    // MARK: - Organizer and attendees

    func testOrganizerNameAndEmail() {
        let parsed = event([
            #"ORGANIZER;CN="Mr Collier";SENT-BY="mailto:office@example.com":MAILTO:collier@example.com"#
        ])

        XCTAssertEqual(parsed?.organizer, "MAILTO:collier@example.com")
        XCTAssertEqual(parsed?.organizerEmail, "collier@example.com")
        XCTAssertEqual(parsed?.organizerName, "Mr Collier")
    }

    func testEventWithoutOrganizer() {
        let parsed = event(["SUMMARY:No organizer"])

        XCTAssertNil(parsed?.organizer)
        XCTAssertNil(parsed?.organizerEmail)
        XCTAssertNil(parsed?.organizerName)
    }

    func testAttendeeStandardParameters() {
        let attendee = event([
            "ATTENDEE;CUTYPE=room;ROLE=OPT-PARTICIPANT;RSVP=FALSE;X-NUM-GUESTS=0:mailto:lr1@example.com"
        ])?.attendees?.first

        XCTAssertEqual(attendee?.calendarUserType, "ROOM")
        XCTAssertEqual(attendee?.role, "OPT-PARTICIPANT")
        XCTAssertEqual(attendee?.rsvp, false)
        // Still available where earlier versions put them
        XCTAssertEqual(attendee?.nonStandardProperties?["CUTYPE"], "room")
        XCTAssertEqual(attendee?.nonStandardProperties?["RSVP"], "FALSE")
        XCTAssertEqual(attendee?.nonStandardProperties?["X-NUM-GUESTS"], "0")
    }

    func testParticipationStatuses() {
        XCTAssertEqual(ParticipationStatus(rawValue: "TENTATIVE"), .tentative)
        XCTAssertEqual(ParticipationStatus(rawValue: "DELEGATED"), .delegated)
        XCTAssertEqual(ParticipationStatus(rawValue: "needs-action"), .needsAction)
        XCTAssertNil(ParticipationStatus(rawValue: "X-UNKNOWN"))
    }

    // MARK: - Calendar properties

    func testVersionAndCalendarScale() {
        let defaults = calendar([], header: [])
        let explicit = calendar([], header: ["VERSION:2.1", "CALSCALE:GREGORIAN"])

        XCTAssertEqual(defaults?.version, "2.0")
        XCTAssertEqual(defaults?.calendarScale, "GREGORIAN")
        XCTAssertEqual(explicit?.version, "2.1")
    }

    // MARK: - DTSTAMP

    func testStampFallsBackToModifiedOrCreatedDate() {
        XCTAssertEqual(
            event(["DTSTAMP:20240103T000000Z", "LAST-MODIFIED:20240102T000000Z"])?.dtStamp,
            Date(timeIntervalSince1970: 1_704_240_000)
        )
        XCTAssertEqual(
            event(["LAST-MODIFIED:20240102T000000Z", "CREATED:20240101T000000Z"])?.dtStamp,
            Date(timeIntervalSince1970: 1_704_153_600)
        )
        XCTAssertEqual(event(["CREATED:20240101T000000Z"])?.dtStamp, Date(timeIntervalSince1970: 1_704_067_200))
    }

    func testMissingStampIsFixed() {
        XCTAssertEqual(event(["SUMMARY:No stamp"])?.dtStamp, .distantPast)
    }

    // MARK: - Recurrence rule validation

    func testInitializerValidatesRuleParts() {
        let invalid = ICRRule(byHour: [9, 99], byMinute: [0, 30], byMonth: [13], frequency: .daily)

        XCTAssertNil(invalid.byHour)
        XCTAssertEqual(invalid.byMinute, [0, 30])
        XCTAssertNil(invalid.byMonth)
    }

    func testInitializerKeepsOnlyUntilWithCount() {
        let rule = ICRRule(count: 3, frequency: .daily, until: .dateTime(from: Date(timeIntervalSince1970: 0)))

        XCTAssertNil(rule.count)
        XCTAssertNotNil(rule.until)
        XCTAssertEqual(ICRRule(count: 3, frequency: .daily).count, 3)
    }

    func testAssignedRulePartsAreValidated() {
        var rule = ICRRule(frequency: .monthly)
        rule.byDayOfMonth = [1, -1]
        XCTAssertEqual(rule.byDayOfMonth, [1, -1])

        rule.byDayOfMonth = [0]
        XCTAssertNil(rule.byDayOfMonth)
    }
}
