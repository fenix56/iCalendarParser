import XCTest
@testable import iCalendarParser

final class CancellationTests: XCTestCase {

    /// A calendar with `count` weekly events
    private func raw(events count: Int, extra: [String] = []) -> String {
        var lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Example//EN"]
        for index in 0..<count {
            lines += [
                "BEGIN:VEVENT", "UID:\(index)", "SUMMARY:Event \(index)",
                "DTSTART:20240101T100000Z", "DTEND:20240101T110000Z", "RRULE:FREQ=WEEKLY",
                "END:VEVENT"
            ]
        }
        lines += extra + ["END:VCALENDAR"]
        return lines.joined(separator: "\r\n")
    }

    /// An event whose rule would take a very long time to expand
    private let endlessRule = [
        "BEGIN:VEVENT", "UID:endless", "DTSTART:20000101T000000Z",
        "RRULE:FREQ=SECONDLY;COUNT=500000000", "END:VEVENT"
    ]

    private let rangeStart = Date(timeIntervalSince1970: 1_704_067_200) // 2024-01-01
    private let rangeEnd = Date(timeIntervalSince1970: 1_704_672_000) // 2024-01-08

    /// Returns `true` after it has been called `limit` times, and counts every call
    private final class CancelAfter {
        let limit: Int
        private(set) var calls = 0

        init(_ limit: Int) {
            self.limit = limit
        }

        func isCancelled() -> Bool {
            calls += 1
            return calls > limit
        }
    }

    // MARK: - Parsing

    func testParsingThrowsWhenCancelled() {
        XCTAssertThrowsError(try ICParser().calendar(from: raw(events: 10)) { true }) { error in
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testParsingWithoutCancellationMatchesSynchronousParsing() throws {
        let raw = raw(events: 50)

        let cancellable = try ICParser().calendar(from: raw) { false }
        let synchronous = ICParser().calendar(from: raw)

        XCTAssertEqual(cancellable?.events.map(\.id), synchronous?.events.map(\.id))
        XCTAssertEqual(cancellable?.events.count, 50)
    }

    func testParsingChecksRegularlyAndStopsAtOnce() {
        let raw = raw(events: 1_000)

        let complete = CancelAfter(.max)
        _ = try? ICParser().calendar(from: raw, isCancelled: complete.isCancelled)
        // At least once per line
        XCTAssertGreaterThan(complete.calls, 7_000)

        let cancelled = CancelAfter(100)
        XCTAssertThrowsError(try ICParser().calendar(from: raw, isCancelled: cancelled.isCancelled))
        XCTAssertEqual(cancelled.calls, 101)
    }

    func testLegacyParsingThrowsWhenCancelled() {
        XCTAssertThrowsError(try ICParser(timeZoneHandling: .legacy).calendar(from: raw(events: 10)) { true })
    }

    // MARK: - Occurrences

    func testOccurrencesThrowWhenCancelled() throws {
        let calendar = try XCTUnwrap(ICParser().calendar(from: raw(events: 10)))

        XCTAssertThrowsError(try calendar.occurrences(from: rangeStart, to: rangeEnd) { true }) { error in
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertThrowsError(try calendar.events[0].occurrences(from: rangeStart, to: rangeEnd) { true })
    }

    func testOccurrencesWithoutCancellationMatchSynchronousOccurrences() throws {
        let calendar = try XCTUnwrap(ICParser().calendar(from: raw(events: 10)))

        let cancellable = try calendar.occurrences(from: rangeStart, to: rangeEnd, includeCancelled: true) { false }
        let synchronous = calendar.occurrences(from: rangeStart, to: rangeEnd, includeCancelled: true)

        XCTAssertEqual(cancellable, synchronous)
        XCTAssertEqual(cancellable.count, 10)
    }

    func testLongExpansionStopsAtOnce() throws {
        let calendar = try XCTUnwrap(ICParser().calendar(from: raw(events: 0, extra: endlessRule)))
        let cancelled = CancelAfter(1_000)

        XCTAssertThrowsError(
            try calendar.occurrences(from: rangeStart, to: rangeEnd, isCancelled: cancelled.isCancelled)
        )
        XCTAssertEqual(cancelled.calls, 1_001)
    }

    func testCancellingTaskStopsExpansion() async throws {
        let calendar = try XCTUnwrap(ICParser().calendar(from: raw(events: 0, extra: endlessRule)))
        let start = rangeStart
        let end = rangeEnd

        let task = Task.detached {
            try calendar.occurrences(from: start, to: end) { Task.isCancelled }
        }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected CancellationError")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }
}
