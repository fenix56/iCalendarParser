import XCTest
@testable import iCalendarParser

/// `RECURRENCE-ID;RANGE=THISANDFUTURE`
final class FutureOverrideTests: XCTestCase {

    private let berlin = TimeZone(identifier: "Europe/Berlin") ?? .current

    /// Weekly on Mondays at 10:00 UTC for 6 weeks, from 2024-01-01
    private let series = [
        "UID:series", "SUMMARY:Old slot", "LOCATION:Room 1",
        "DTSTART:20240101T100000Z", "DTEND:20240101T110000Z", "RRULE:FREQ=WEEKLY;COUNT=6"
    ]

    private func calendar(_ events: [[String]]) -> ICalendar? {
        var lines: [String] = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Example//EN"]
        for event in events {
            lines += ["BEGIN:VEVENT"] + event + ["END:VEVENT"]
        }
        lines.append("END:VCALENDAR")
        return ICParser().calendar(from: lines.joined(separator: "\r\n"))
    }

    private func utc(_ value: String) -> Date {
        WallClock(value)?.date(offset: 0) ?? .distantPast
    }

    private func occurrences(_ events: [[String]], includeCancelled: Bool = false) -> [ICOccurrence] {
        calendar(events)?.occurrences(
            from: utc("20231201T000000"),
            to: utc("20240401T000000"),
            includeCancelled: includeCancelled
        ) ?? []
    }

    // MARK: - Parsing

    func testParsesRange() {
        let events = calendar([
            series,
            ["UID:series", "RECURRENCE-ID;RANGE=THISANDFUTURE:20240115T100000Z", "DTSTART:20240115T100000Z"],
            ["UID:series", "RECURRENCE-ID:20240122T100000Z", "DTSTART:20240122T100000Z"]
        ])?.events

        XCTAssertEqual(events?.map(\.appliesToFutureOccurrences), [false, true, false])
    }

    // MARK: - Expansion

    func testChangeAppliesToLaterOccurrences() {
        // From 15 January the meeting moves to Tuesdays 14:00-16:00 in another room
        let result = occurrences([
            series,
            [
                "UID:series", "SUMMARY:New slot", "LOCATION:Room 2",
                "RECURRENCE-ID;RANGE=THISANDFUTURE:20240115T100000Z",
                "DTSTART:20240116T140000Z", "DTEND:20240116T160000Z"
            ]
        ])

        XCTAssertEqual(result.map(\.start), [
            utc("20240101T100000"), utc("20240108T100000"),
            utc("20240116T140000"), utc("20240123T140000"), utc("20240130T140000"), utc("20240206T140000")
        ])
        XCTAssertEqual(result.map(\.event.summary), [
            "Old slot", "Old slot", "New slot", "New slot", "New slot", "New slot"
        ])
        XCTAssertEqual(result.map(\.event.location).last, "Room 2")
        XCTAssertEqual(result.last?.end, utc("20240206T160000"))
        XCTAssertEqual(result.last?.originalStart, utc("20240205T100000"))
    }

    func testSingleOverrideStillAppliesAfterChange() {
        let result = occurrences([
            series,
            [
                "UID:series", "SUMMARY:New slot",
                "RECURRENCE-ID;RANGE=THISANDFUTURE:20240115T100000Z",
                "DTSTART:20240115T120000Z", "DTEND:20240115T130000Z"
            ],
            [
                "UID:series", "SUMMARY:One-off",
                "RECURRENCE-ID:20240129T100000Z",
                "DTSTART:20240131T090000Z", "DTEND:20240131T100000Z"
            ]
        ])

        XCTAssertEqual(result.map(\.event.summary), [
            "Old slot", "Old slot", "New slot", "New slot", "One-off", "New slot"
        ])
        XCTAssertEqual(result[4].start, utc("20240131T090000"))
    }

    func testLaterChangeReplacesEarlierOne() {
        let result = occurrences([
            series,
            [
                "UID:series", "SUMMARY:Second slot", "RECURRENCE-ID;RANGE=THISANDFUTURE:20240108T100000Z",
                "DTSTART:20240108T110000Z", "DTEND:20240108T120000Z"
            ],
            [
                "UID:series", "SUMMARY:Third slot", "RECURRENCE-ID;RANGE=THISANDFUTURE:20240122T100000Z",
                "DTSTART:20240122T150000Z", "DTEND:20240122T160000Z"
            ]
        ])

        XCTAssertEqual(result.map(\.event.summary), [
            "Old slot", "Second slot", "Second slot", "Third slot", "Third slot", "Third slot"
        ])
        XCTAssertEqual(result.last?.start, utc("20240205T150000"))
    }

    func testCancellingEndsSeries() {
        let events = [
            series,
            ["UID:series", "RECURRENCE-ID;RANGE=THISANDFUTURE:20240122T100000Z", "DTSTART:20240122T100000Z",
             "STATUS:CANCELLED"]
        ]

        XCTAssertEqual(occurrences(events).map(\.start), [
            utc("20240101T100000"), utc("20240108T100000"), utc("20240115T100000")
        ])
        XCTAssertEqual(occurrences(events, includeCancelled: true).count, 6)
    }

    func testChangeWithoutEndKeepsSeriesLength() {
        let result = occurrences([
            series,
            ["UID:series", "SUMMARY:Later", "RECURRENCE-ID;RANGE=THISANDFUTURE:20240122T100000Z",
             "DTSTART:20240122T130000Z"]
        ])

        XCTAssertEqual(result.last?.start, utc("20240205T130000"))
        XCTAssertEqual(result.last?.end, utc("20240205T140000"))
    }

    func testShiftKeepsLocalTimeAcrossDaylightSaving() {
        // Weekly 10:00 Berlin, moved to 11:00 from 18 March; after 31 March that is 11:00 CEST
        let result = calendar([
            ["UID:berlin", "DTSTART;TZID=Europe/Berlin:20240304T100000", "RRULE:FREQ=WEEKLY;COUNT=6"],
            ["UID:berlin", "RECURRENCE-ID;TZID=Europe/Berlin;RANGE=THISANDFUTURE:20240318T100000",
             "DTSTART;TZID=Europe/Berlin:20240318T110000"]
        ])?.occurrences(from: utc("20240301T000000"), to: utc("20240501T000000")) ?? []

        let local = result.map { WallClock(date: $0.start, offset: berlin.secondsFromGMT(for: $0.start)).hour }
        XCTAssertEqual(local, [10, 10, 11, 11, 11, 11])
    }

    func testOccurrenceMovedIntoRangeIsFound() {
        // The 5 February occurrence moves to 3 February, inside a range that ends before the original time
        let result = calendar([
            series,
            ["UID:series", "SUMMARY:Saturday", "RECURRENCE-ID;RANGE=THISANDFUTURE:20240129T100000Z",
             "DTSTART:20240127T100000Z", "DTEND:20240127T110000Z"]
        ])?.occurrences(from: utc("20240201T000000"), to: utc("20240204T000000"))

        XCTAssertEqual(result?.map(\.start), [utc("20240203T100000")])
        XCTAssertEqual(result?.first?.originalStart, utc("20240205T100000"))
    }
}
