import XCTest
@testable import iCalendarParser

final class DataInputTests: XCTestCase {

    private func data(_ lines: [String]) -> Data {
        let calendar = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Example//EN"] + lines + ["END:VCALENDAR"]
        return Data(calendar.joined(separator: "\r\n").utf8)
    }

    /// A calendar whose SUMMARY is folded between the bytes of `split`, as RFC 5545 allows
    private func dataWithSplitCharacter(_ split: String, splitAfter byteCount: Int) -> Data {
        let bytes = Array(split.utf8)
        var raw = Data("BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Example//EN\r\n".utf8)
        raw.append(contentsOf: Array("BEGIN:VEVENT\r\nUID:1\r\nSUMMARY:".utf8))
        raw.append(contentsOf: bytes[..<byteCount])
        raw.append(contentsOf: Array("\r\n ".utf8))
        raw.append(contentsOf: bytes[byteCount...])
        raw.append(contentsOf: Array(" Accelerated Reader\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n".utf8))
        return raw
    }

    func testCharacterSplitAcrossFoldedLineIsRestored() {
        let raw = dataWithSplitCharacter("📖", splitAfter: 2)

        // Converting the whole file first fails, because the split bytes are not valid UTF-8
        XCTAssertNil(String(data: raw, encoding: .utf8))
        XCTAssertEqual(ICParser().calendar(from: raw)?.events.first?.summary, "📖 Accelerated Reader")
    }

    func testTwoByteCharacterSplitAcrossFoldedLineIsRestored() {
        let raw = dataWithSplitCharacter("é", splitAfter: 1)

        XCTAssertEqual(ICParser().calendar(from: raw)?.events.first?.summary, "é Accelerated Reader")
    }

    func testDataAndStringInputGiveSameResult() throws {
        let lines = [
            "BEGIN:VEVENT", "UID:1", "SUMMARY:Film club 🍿", "DTSTART;TZID=Europe/London:20240925T151500",
            "DESCRIPTION:Line one\\nLine two", " folded", "RRULE:FREQ=WEEKLY;BYDAY=FR", "END:VEVENT"
        ]
        let raw = data(lines)
        let string = try XCTUnwrap(String(data: raw, encoding: .utf8))

        let fromData = try XCTUnwrap(ICParser().calendar(from: raw))
        let fromString = try XCTUnwrap(ICParser().calendar(from: string))

        XCTAssertEqual(fromData.events.map(\.summary), fromString.events.map(\.summary))
        XCTAssertEqual(fromData.events.map(\.description), fromString.events.map(\.description))
        XCTAssertEqual(fromData.events.map(\.dtStart), fromString.events.map(\.dtStart))
        XCTAssertEqual(fromData.events.first?.recurrenceRule, fromString.events.first?.recurrenceRule)
    }

    func testInvalidUTF8IsReplaced() {
        var raw = Data("BEGIN:VCALENDAR\r\nPRODID:-//Example//EN\r\nBEGIN:VEVENT\r\nUID:1\r\nSUMMARY:Caf".utf8)
        raw.append(0xE9) // "é" in Latin-1, not valid UTF-8
        raw.append(contentsOf: Array("\r\nEND:VEVENT\r\nEND:VCALENDAR".utf8))

        XCTAssertEqual(ICParser().calendar(from: raw)?.events.first?.summary, "Caf\u{FFFD}")
    }

    func testByteOrderMarkIsIgnored() {
        var raw = Data([0xEF, 0xBB, 0xBF])
        raw.append(data(["BEGIN:VEVENT", "UID:1", "END:VEVENT"]))

        XCTAssertEqual(ICParser().calendar(from: raw)?.events.count, 1)
    }

    func testEmptyDataIsNotACalendar() {
        XCTAssertNil(ICParser().calendar(from: Data()))
    }

    func testParsingDataThrowsWhenCancelled() {
        XCTAssertThrowsError(try ICParser().calendar(from: data([])) { true }) { error in
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertNotNil(try ICParser(timeZoneHandling: .legacy).calendar(from: data([])) { false })
    }
}
