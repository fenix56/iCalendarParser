# iCalendarParser

<p>
    <a href="https://github.com/dmail-me/iCalendarParser/actions">
      <img src="https://github.com/dmail-me/iCalendarParser/workflows/ci/badge.svg?branch=main">
    </a>
    <img src="https://img.shields.io/badge/Swift-6.0-ff69b4.svg" />
    <img src="https://img.shields.io/badge/license-MIT-black.svg" />
</p>

A [RFC 5545](https://www.ietf.org/rfc/rfc5545.txt) compatible parser for iCalendar files in Swift.

## Installation

To use `iCalendarParser` just add it as Swift Package Manager dependency:

### via Xcode

Open your project, click on File → Add Packages, enter the repository URL (`https://github.com/dmail-me/iCalendarParser.git`), and add the package product to your app target.

### via SPM Package.swift

```swift
dependencies: [
    .package(
      name: "iCalendarParser",
      url: "https://github.com/dmail-me/iCalendarParser",
      from: "0.1.0"
    )
]
```

## Usage

To get started with iCalendarParser, all you have to do is to import it and use its `ICParser` type to convert any ICS file into iCalendar object:

```swift
import iCalendarParser

let rawICS: String = ...
let parser = ICParser()
let calendar: ICalendar? = parser.calendar(from: rawICS)
```

### Upcoming events

`occurrences(from:to:)` expands recurring events and returns every occurrence in a date range, sorted by start:

```swift
let today = Calendar.current.startOfDay(for: Date())
let nextWeek = Calendar.current.date(byAdding: .day, value: 7, to: today)!

for occurrence in calendar?.occurrences(from: today, to: nextWeek) ?? [] {
    print(occurrence.event.summary ?? "", occurrence.start, occurrence.end, occurrence.isAllDay)
}
```

It supports every `RRULE` frequency and rule part, adds `RDATE` and removes `EXDATE` dates, replaces moved or changed occurrences with their `RECURRENCE-ID` event, takes the length from `DTEND` or `DURATION`, and skips cancelled events unless `includeCancelled` is `true`. Recurrences keep their local time across daylight saving transitions.

### Time zones

By default, dates follow RFC 5545: a time without `Z` or `TZID` is local time on the device, and a `TZID` is resolved as a system time zone or with the calendar's `VTIMEZONE` definitions.

Apps that relied on the earlier behaviour can opt in to it:

```swift
let parser = ICParser(timeZoneHandling: .legacy)
```

With `.legacy`, a time without `Z` or `TZID` is read as UTC, a `TZID` that is not a system time zone identifier is read in the device's time zone, and `VTIMEZONE` components are not parsed.

## Is it production ready?

iCalendarParser is currently not feature complete yet. While it requires an additional implementation to be fully compatible with RFC5545, we appreciate contributions from the community to help us improve the library. 

However, it's worth noting that the library is being used in production within the [Dmail.me app](https://apps.apple.com/us/app/dmail-me-dm-the-world/id6444334972), and we are committed to constantly improving it.

## TODO

- Parse To-Do, Journal, Free/Busy, and Alarm components
- Add additional properties in `ICEvent`

## Contributing

Contributions to iCalendarParser are welcomed and encouraged!

## License

iCalendarParser is available under the MIT license. See [LICENSE](LICENSE) for more information.

## Credits

- [chan614/iCalSwift](https://github.com/chan614/iCalSwift) (Inspired to create an initial implementation)

