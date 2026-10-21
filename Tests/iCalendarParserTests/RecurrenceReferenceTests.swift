import XCTest
@testable import iCalendarParser

/// Compares recurrence expansion with reference results from python-dateutil
final class RecurrenceReferenceTests: XCTestCase {

    func testMatchesReferenceImplementation() throws {
        for testCase in RecurrenceReferenceCases.cases {
            let dtStart = try XCTUnwrap(PropertyBuilder.buildDateTime(from: ("DTSTART", testCase.start + "Z")))
            let rule = try XCTUnwrap(PropertyBuilder.buildRRule(from: ("RRULE", testCase.rule)), testCase.rule)
            let event = ICEvent(dtStart: dtStart, recurrenceRule: rule)

            let last = try XCTUnwrap(WallClock(try XCTUnwrap(testCase.expected.last))).date(offset: 0)
            // For a finished rule, look well past the last occurrence to catch extra ones
            let end = testCase.isComplete ? last.addingTimeInterval(10 * 366 * 86_400) : last.addingTimeInterval(1)

            let starts = event.occurrences(from: dtStart.date, to: end).map { format($0.start) }

            XCTAssertEqual(starts, testCase.expected, "\(testCase.start) \(testCase.rule)")
        }
    }

    private func format(_ date: Date) -> String {
        let wallClock = WallClock(date: date, offset: 0)
        let date = WallClock.civilDate(daysSince1970: wallClock.daysSince1970)
        return String(
            format: "%04d%02d%02dT%02d%02d%02d",
            date.year, date.month, date.day, wallClock.hour, wallClock.minute, wallClock.second
        )
    }
}
