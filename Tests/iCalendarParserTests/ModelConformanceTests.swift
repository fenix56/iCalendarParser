import XCTest
@testable import iCalendarParser

final class ModelConformanceTests: XCTestCase {

    private let raw = [
        "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Example//EN",
        "BEGIN:VTIMEZONE", "TZID:Custom",
        "BEGIN:STANDARD", "DTSTART:19700101T000000", "TZOFFSETFROM:+0100", "TZOFFSETTO:+0100", "END:STANDARD",
        "END:VTIMEZONE",
        "BEGIN:VEVENT", "UID:series", "SUMMARY:Weekly", "DTSTART:20240101T100000Z", "RRULE:FREQ=WEEKLY", "END:VEVENT",
        "BEGIN:VEVENT", "UID:series", "SUMMARY:Moved", "RECURRENCE-ID:20240108T100000Z",
        "DTSTART:20240109T100000Z", "END:VEVENT",
        "BEGIN:VEVENT", "SUMMARY:No UID A", "END:VEVENT",
        "BEGIN:VEVENT", "SUMMARY:No UID B", "END:VEVENT",
        "END:VCALENDAR"
    ].joined(separator: "\r\n")

    private func parse() throws -> ICalendar {
        try XCTUnwrap(ICParser().calendar(from: raw))
    }

    private func withoutStamp(_ event: ICEvent) -> ICEvent {
        var event = event
        event.dtStamp = .distantPast
        return event
    }

    // MARK: - Equatable

    func testSameInputParsesToEqualValues() throws {
        let first = try parse()
        let second = try parse()

        // DTSTAMP is missing, so it is filled in with the parse time
        XCTAssertEqual(first.events.map(withoutStamp), second.events.map(withoutStamp))
        XCTAssertEqual(first.timeZones, second.timeZones)
    }

    func testEventsWithSameUIDAreNotEqualWhenTheyDiffer() throws {
        let events = try parse().events

        XCTAssertNotEqual(events[0], events[1])
        XCTAssertNotEqual(events[2], events[3])
    }

    func testChangedPropertyMakesEventsDifferent() throws {
        let event = try XCTUnwrap(try parse().events.first)
        var changed = event
        changed.location = "Room 2"

        XCTAssertNotEqual(event, changed)
        XCTAssertEqual(event.id, changed.id)
    }

    func testChangedDefinitionMakesTimeZonesDifferent() throws {
        let timeZone = try XCTUnwrap(try parse().uniqueTimeZone)
        var changed = timeZone
        changed.standard?.timeZoneOffsetTo = "+0200"

        XCTAssertNotEqual(timeZone, changed)
        XCTAssertEqual(timeZone.id, changed.id)
    }

    // MARK: - Identifiable

    func testRecurringEventAndItsChangedOccurrenceHaveDifferentIDs() throws {
        let events = try parse().events

        XCTAssertEqual(events[0].id, ICEvent.ID(uid: "series"))
        let movedFrom = Date(timeIntervalSince1970: 1_704_708_000) // 2024-01-08 10:00 UTC
        XCTAssertEqual(events[1].id, ICEvent.ID(uid: "series", recurrenceId: movedFrom))
        XCTAssertEqual(Set(events.prefix(2).map(\.id)).count, 2)
    }

    func testTimeZoneIDIsTimeZoneIdentifier() throws {
        XCTAssertEqual(try parse().uniqueTimeZone?.id, "Custom")
    }

    // MARK: - Sendable

    func testParsedValuesCanBeSentAcrossConcurrencyDomains() async throws {
        let calendar = try parse()
        let parser = ICParser(timeZoneHandling: .legacy)
        let rawCalendar = raw

        // Compiles only when the models are Sendable (Swift 6 language mode)
        let count = await Task.detached {
            calendar.events.count + (parser.calendar(from: rawCalendar)?.events.count ?? 0)
        }.value
        let start = Date(timeIntervalSince1970: 1_704_067_200) // 2024-01-01
        let end = Date(timeIntervalSince1970: 1_705_276_800) // 2024-01-15
        let occurrences = await Task.detached {
            calendar.occurrences(from: start, to: end)
        }.value

        XCTAssertEqual(count, 8)
        XCTAssertEqual(occurrences.map(\.event.summary), ["Weekly", "Moved"])
    }
}
