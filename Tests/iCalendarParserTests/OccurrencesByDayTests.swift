import XCTest
@testable import iCalendarParser

final class OccurrencesByDayTests: XCTestCase {

    /// A Gregorian calendar in the device's time zone, like `Calendar.current`
    private var deviceCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    private func calendar(_ events: [[String]]) -> ICalendar? {
        var lines: [String] = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Example//EN"]
        for event in events {
            lines += ["BEGIN:VEVENT"] + event + ["END:VEVENT"]
        }
        lines.append("END:VCALENDAR")
        return ICParser().calendar(from: lines.joined(separator: "\r\n"))
    }

    /// A wall-clock time in the device's time zone
    private func local(_ value: String) -> Date {
        WallClock(value)?.date(in: .current) ?? .distantPast
    }

    private func summaries(_ day: ICDay) -> [String] {
        day.occurrences.map { $0.occurrence.event.summary ?? "" }
    }

    // MARK: - Multi-day events

    func testMultiDayEventsAreListedOnEachDay() throws {
        let cal = try XCTUnwrap(calendar([
            ["UID:trip", "SUMMARY:School trip", "DTSTART;VALUE=DATE:20260925", "DTEND;VALUE=DATE:20260928"],
            ["UID:camp", "SUMMARY:Camp", "DTSTART:20260925T160000", "DTEND:20260927T100000"],
            ["UID:club", "SUMMARY:Film club", "DTSTART:20260925T151500", "DTEND:20260925T174500"]
        ]))

        let days = cal.occurrencesByDay(from: local("20260924T000000"), days: 5, calendar: deviceCalendar)

        XCTAssertEqual(days.map(\.date), (24...28).map { local("202609\($0)T000000") })
        XCTAssertEqual(days.map(summaries), [
            [],
            ["School trip", "Film club", "Camp"],
            ["School trip", "Camp"],
            ["School trip", "Camp"],
            []
        ])

        let trip = days[1...3].map { $0.occurrences[0] }
        XCTAssertEqual(trip.map(\.part), [.start, .middle, .end])
        XCTAssertEqual(trip.map(\.dayNumber), [1, 2, 3])
        XCTAssertEqual(trip.map(\.dayCount), [3, 3, 3])

        let camp = days[1...3].compactMap { day in day.occurrences.first { $0.occurrence.event.uid == "camp" } }
        XCTAssertEqual(camp.map(\.part), [.start, .middle, .end])

        let club = days[1].occurrences[1]
        XCTAssertEqual(club.part, .whole)
        XCTAssertEqual(club.dayNumber, 1)
        XCTAssertEqual(club.dayCount, 1)
    }

    func testSingleAllDayEventIsWhole() throws {
        let cal = try XCTUnwrap(calendar([["UID:1", "SUMMARY:Holiday", "DTSTART;VALUE=DATE:20260925"]]))

        let days = cal.occurrencesByDay(from: local("20260924T000000"), days: 3, calendar: deviceCalendar)

        XCTAssertEqual(days.map(summaries), [[], ["Holiday"], []])
        XCTAssertEqual(days[1].occurrences.first?.part, .whole)
    }

    // MARK: - Ranges

    func testFirstDayStartsAtGivenTime() throws {
        let cal = try XCTUnwrap(calendar([
            ["UID:ended", "SUMMARY:Ended", "DTSTART:20260925T090000", "DTEND:20260925T100000"],
            ["UID:running", "SUMMARY:Running", "DTSTART:20260925T140000", "DTEND:20260925T141500"],
            ["UID:later", "SUMMARY:Later", "DTSTART:20260925T153000", "DTEND:20260925T163000"],
            ["UID:tomorrow", "SUMMARY:Tomorrow", "DTSTART:20260926T100000", "DTEND:20260926T120000"]
        ]))

        // "What's on today" at 14:05
        let today = cal.occurrencesByDay(from: local("20260925T140500"), days: 1, calendar: deviceCalendar)

        XCTAssertEqual(today.count, 1)
        XCTAssertEqual(today.first?.date, local("20260925T000000"))
        XCTAssertEqual(today.first.map(summaries), ["Running", "Later"])
        // It started today, before the given time
        XCTAssertEqual(today.first?.occurrences.first?.part, .whole)
    }

    func testRecurringEventsInWeek() throws {
        let cal = try XCTUnwrap(calendar([
            ["UID:bike", "SUMMARY:Bike Tuition", "DTSTART:20260906T100000", "DTEND:20260906T120000",
             "RRULE:FREQ=WEEKLY;BYDAY=SU", "EXDATE:20261004T100000"]
        ]))

        let days = cal.occurrencesByDay(from: local("20260926T000000"), days: 14, calendar: deviceCalendar)

        XCTAssertEqual(days.count, 14)
        XCTAssertEqual(days.filter { !$0.occurrences.isEmpty }.map(\.date), [local("20260927T000000")])
    }

    func testDaysFollowDaylightSavingTransition() throws {
        var berlinCalendar = Calendar(identifier: .gregorian)
        berlinCalendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Berlin"))
        let berlin = berlinCalendar.timeZone
        let cal = try XCTUnwrap(calendar([
            ["UID:sunday", "SUMMARY:Sunday", "DTSTART;TZID=Europe/Berlin:20240331T233000",
             "DTEND;TZID=Europe/Berlin:20240331T234500"],
            ["UID:monday", "SUMMARY:Monday", "DTSTART;TZID=Europe/Berlin:20240401T003000",
             "DTEND;TZID=Europe/Berlin:20240401T010000"]
        ]))

        let start = try XCTUnwrap(WallClock("20240331T000000")).date(in: berlin)
        let days = cal.occurrencesByDay(from: start, days: 2, calendar: berlinCalendar)

        // 31 March 2024 has 23 hours in Berlin; a 24-hour day would end at 01:00 on 1 April
        XCTAssertEqual(days[1].date.timeIntervalSince(days[0].date), 23 * 3_600)
        XCTAssertEqual(days.map(summaries), [["Sunday"], ["Monday"]])
    }

    func testNoDays() throws {
        let cal = try XCTUnwrap(calendar([["UID:1", "DTSTART:20260925T100000"]]))

        XCTAssertEqual(cal.occurrencesByDay(from: local("20260925T000000"), days: 0).count, 0)
    }

    // MARK: - Cancelled

    func testCancelledEventsAreSkippedUnlessIncluded() throws {
        let cal = try XCTUnwrap(calendar([
            ["UID:1", "SUMMARY:Cancelled", "DTSTART:20260925T100000", "STATUS:CANCELLED"]
        ]))
        let start = local("20260925T000000")

        XCTAssertEqual(cal.occurrencesByDay(from: start, days: 1, calendar: deviceCalendar)[0].occurrences.count, 0)
        XCTAssertEqual(
            cal.occurrencesByDay(from: start, days: 1, calendar: deviceCalendar, includeCancelled: true)[0]
                .occurrences.count,
            1
        )
    }

    func testThrowsWhenCancelled() throws {
        let cal = try XCTUnwrap(calendar([["UID:1", "DTSTART:20260925T100000"]]))

        XCTAssertThrowsError(try cal.occurrencesByDay(from: local("20260925T000000"), days: 7) { true }) { error in
            XCTAssertTrue(error is CancellationError)
        }
    }
}
