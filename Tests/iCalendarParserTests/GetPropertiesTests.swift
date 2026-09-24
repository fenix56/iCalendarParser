import XCTest
@testable import iCalendarParser

final class GetPropertiesTests: XCTestCase {
    func testCreateProperties() {
        let rawIcs = """
        BEGIN:VCALENDAR\r\nPRODID:-//Example Inc//Calendar//EN\r\nVERSION:2.0
        """

        let parser = ICParser()
        let properties = parser.getProperties(from: rawIcs)

        XCTAssertTrue(!properties.isEmpty)
        XCTAssertEqual(properties.count, 3)
    }

    func testPropertiesShouldNotIncludeSpace() {
        let rawIcs = """
        ATTENDEE;CUTYPE=INDIVIDUAL;ROLE=REQ-PARTICIPANT;PARTSTAT=ACCEPTED;
        RSVP=TRUE\r\n ;CN=example@mail.com;X-NUM-GUESTS=0:mailto:example@mail.com
        """

        let parser = ICParser()
        let properties = parser.getProperties(from: rawIcs)

        XCTAssertTrue(properties.filter { $0.name.contains(" ")}.isEmpty)
    }

    func testCreatePropertiesWithNewLine() {
        let rawIcs = """
        ATTENDEE;CUTYPE=INDIVIDUAL;ROLE=REQ-PARTICIPANT;PARTSTAT=ACCEPTED;RSVP=\
        TRUE\r\n ;CN=example@mail.com;X-NUM-GUESTS=0:mailto:example@mail.com
        """

        let parser = ICParser()
        let properties = parser.getProperties(from: rawIcs)

        XCTAssertTrue(!properties.isEmpty)
        XCTAssertEqual(properties.count, 1)

        let name = """
        ATTENDEE;CUTYPE=INDIVIDUAL;ROLE=REQ-PARTICIPANT;PARTSTAT=\
        ACCEPTED;RSVP=TRUE;CN=example@mail.com;X-NUM-GUESTS=0
        """
        XCTAssertEqual(properties.first?.name, name)
    }

    func testPropertyValueKeepsColons() {
        let rawIcs = "URL:https://example.com:8080/event\r\nDESCRIPTION:Time: 10:00"

        let properties = ICParser().getProperties(from: rawIcs)

        XCTAssertEqual(properties.count, 2)
        XCTAssertEqual(properties.first?.name, "URL")
        XCTAssertEqual(properties.first?.value, "https://example.com:8080/event")
        XCTAssertEqual(properties.last?.value, "Time: 10:00")
    }

    func testLinesWithoutValueAreSkipped() {
        let rawIcs = "BEGIN:VCALENDAR\r\nDESCRIPTION:\r\nNO-SEPARATOR\r\n\r\nEND:VCALENDAR"

        let properties = ICParser().getProperties(from: rawIcs)

        XCTAssertEqual(properties.map(\.name), ["BEGIN", "END"])
    }
}
