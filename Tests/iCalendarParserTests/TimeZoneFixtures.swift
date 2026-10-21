/// `VTIMEZONE` definitions shared by the time zone tests
enum TimeZoneFixtures {

    /// Outlook / Exchange style definition with a Windows time zone name
    static let windowsEurope = [
        "BEGIN:VTIMEZONE",
        "TZID:W. Europe Standard Time",
        "BEGIN:STANDARD",
        "DTSTART:16010101T030000",
        "TZOFFSETFROM:+0200",
        "TZOFFSETTO:+0100",
        "RRULE:FREQ=YEARLY;INTERVAL=1;BYDAY=-1SU;BYMONTH=10",
        "END:STANDARD",
        "BEGIN:DAYLIGHT",
        "DTSTART:16010101T020000",
        "TZOFFSETFROM:+0100",
        "TZOFFSETTO:+0200",
        "RRULE:FREQ=YEARLY;INTERVAL=1;BYDAY=-1SU;BYMONTH=3",
        "END:DAYLIGHT",
        "END:VTIMEZONE"
    ]

    /// Apple style definition with a custom identifier
    static let customEastern = [
        "BEGIN:VTIMEZONE",
        "TZID:US-Eastern-Custom",
        "BEGIN:DAYLIGHT",
        "TZOFFSETFROM:-0500",
        "RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=2SU",
        "DTSTART:20070311T020000",
        "TZNAME:EDT",
        "TZOFFSETTO:-0400",
        "END:DAYLIGHT",
        "BEGIN:STANDARD",
        "TZOFFSETFROM:-0400",
        "RRULE:FREQ=YEARLY;BYMONTH=11;BYDAY=1SU",
        "DTSTART:20071104T020000",
        "TZNAME:EST",
        "TZOFFSETTO:-0500",
        "END:STANDARD",
        "END:VTIMEZONE"
    ]

    /// Lotus Notes style definition with the US rules before and since 2007
    static let historicEastern = [
        "BEGIN:VTIMEZONE",
        "TZID:Eastern",
        "BEGIN:STANDARD",
        "DTSTART:19671029T020000",
        "TZOFFSETFROM:-0400",
        "TZOFFSETTO:-0500",
        "RRULE:FREQ=YEARLY;BYMONTH=10;BYDAY=-1SU;UNTIL=20061029T060000Z",
        "TZNAME:EST",
        "END:STANDARD",
        "BEGIN:DAYLIGHT",
        "DTSTART:19870405T020000",
        "TZOFFSETFROM:-0500",
        "TZOFFSETTO:-0400",
        "RRULE:FREQ=YEARLY;BYMONTH=4;BYDAY=1SU;UNTIL=20060402T070000Z",
        "TZNAME:EDT",
        "END:DAYLIGHT",
        "BEGIN:STANDARD",
        "DTSTART:20071104T020000",
        "TZOFFSETFROM:-0400",
        "TZOFFSETTO:-0500",
        "RRULE:FREQ=YEARLY;BYMONTH=11;BYDAY=1SU",
        "TZNAME:EST",
        "END:STANDARD",
        "BEGIN:DAYLIGHT",
        "DTSTART:20070311T020000",
        "TZOFFSETFROM:-0500",
        "TZOFFSETTO:-0400",
        "RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=2SU",
        "TZNAME:EDT",
        "END:DAYLIGHT",
        "END:VTIMEZONE"
    ]
}
