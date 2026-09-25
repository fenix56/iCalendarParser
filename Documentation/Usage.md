# Using iCalendarParser

A short guide to parsing calendars and listing upcoming events.

- [Requirements](#requirements)
- [Parsing a calendar](#parsing-a-calendar)
- [Time zones](#time-zones)
- [Listing occurrences](#listing-occurrences)
- [Multi-day events](#multi-day-events)
- [Cancellation](#cancellation)
- [Concurrency](#concurrency)
- [Identity and equality](#identity-and-equality)
- [Migrating from 0.3.0](#migrating-from-030)

## Requirements

- Swift 6 toolchain (Xcode 16 or later)
- iOS 15, tvOS 15, macOS 12 or watchOS 8

## Parsing a calendar

```swift
import iCalendarParser

let parser = ICParser()
guard let calendar = parser.calendar(from: rawICS) else {
    // Not an iCalendar object (for example, no PRODID)
    return
}

for event in calendar.events {
    print(event.summary ?? "", event.dtStart?.date ?? .distantPast)
}
```

The parser accepts CRLF, LF and CR line endings, folded lines (space or tab), quoted parameters
such as `CN="Doe, John"`, and a byte order mark. `SUMMARY`, `DESCRIPTION` and `LOCATION` are
returned unescaped, with real line breaks, commas and semicolons.

Besides the existing properties, `ICEvent` has:

| Property | From |
|---|---|
| `duration: ICDuration?` | `DURATION`, when there is no `DTEND` |
| `exceptionDates: [ICDateTime]` | `EXDATE`: occurrences removed from a recurring event |
| `recurrenceDates: [ICDateTime]` | `RDATE`: occurrences added to a recurring event |
| `recurrenceRule: ICRRule?` | `RRULE` |
| `appliesToFutureOccurrences: Bool` | `RECURRENCE-ID;RANGE=THISANDFUTURE` |
| `isCancelled: Bool` | `STATUS:CANCELLED` |

`calendar.timeZones` holds the `VTIMEZONE` definitions of the calendar.

## Time zones

`ICParser(timeZoneHandling:)` decides how times are bound to a time zone.

| Value in the file | `.standard` (default) | `.legacy` |
|---|---|---|
| `20240115T100000Z` | UTC | UTC |
| `TZID=Europe/London:20240115T100000` | that zone | that zone |
| `20240115T100000` (no `Z`, no `TZID`) | device time zone | **UTC** |
| `TZID=W. Europe Standard Time` with a `VTIMEZONE` | the `VTIMEZONE` rules | device time zone |
| Unknown `TZID` without a `VTIMEZONE` | device time zone | device time zone |
| `calendar.timeZones` | parsed | empty |

`.standard` follows RFC 5545. `.legacy` parses dates exactly as version 0.3.0 did; use it where
existing feeds rely on that behaviour, as the Players App does:

```swift
let parser = ICParser(timeZoneHandling: .legacy)
```

`ICDateTime.isFloating` is `true` when a time is not bound to a time zone, and `tzId` keeps the
original `TZID`.

## Listing occurrences

`occurrences(from:to:)` returns every occurrence that overlaps the range, sorted by start:

```swift
let now = Date()
let endOfToday = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))!

for occurrence in calendar.occurrences(from: now, to: endOfToday) {
    print(occurrence.event.summary ?? "", occurrence.start, occurrence.end, occurrence.isAllDay)
}
```

Each `ICOccurrence` has:

| Property | Meaning |
|---|---|
| `event` | The event to display: the recurring event, or the event that changed this occurrence |
| `start`, `end` | When this occurrence starts and ends |
| `originalStart` | When it started before it was moved; equal to `start` unless moved |
| `isAllDay` | `DTSTART` is a date without a time |

What is taken into account:

- **Recurrence rules**: every `RRULE` frequency and rule part, including "2nd Tuesday"
  (`BYDAY=2TU`), "last Friday" (`BYDAY=-1FR`), `BYSETPOS`, `COUNT` and `UNTIL`.
- **Added and removed dates**: `RDATE` adds occurrences, `EXDATE` removes them.
- **Moved or changed occurrences**: an event with the same `UID` and a `RECURRENCE-ID` replaces
  the occurrence that originally started at that time, both at its old and its new time.
- **This and future changes**: with `RANGE=THISANDFUTURE`, the change also applies to every later
  occurrence, which moves by as much as the changed one moved.
- **Cancelled events**: events with `STATUS:CANCELLED` are skipped. Pass `includeCancelled: true`
  to keep them and show them as cancelled.
- **Length**: from `DTEND`, or from `DURATION`. An all-day event without an end lasts one day.
- **Events in progress**: an occurrence that started before `from` and has not ended is included.
- **Daylight saving**: a weekly 10:00 event stays at 10:00 local time across the change.

`event.occurrences(from:to:)` expands a single event without the changes from other events.

### Day and week views

Ask for the whole range once and group by day, rather than asking once per day:

```swift
let calendarSystem = Calendar.current
let tomorrow = calendarSystem.date(byAdding: .day, value: 1, to: calendarSystem.startOfDay(for: Date()))!
let weekEnd = calendarSystem.date(byAdding: .day, value: 6, to: tomorrow)!

let thisWeek = calendar.occurrences(from: tomorrow, to: weekEnd)
```

## Multi-day events

An event that lasts several days is **one** occurrence: an all-day event from 25 to 27 September
starts at midnight on the 25th and ends at midnight on the 28th. A query for any single day
includes it. To show it on every day of a week view, add it to each day it overlaps:

```swift
func occurrencesByDay(_ occurrences: [ICOccurrence], from start: Date, days: Int) -> [Date: [ICOccurrence]] {
    let calendar = Calendar.current
    var result = [Date: [ICOccurrence]]()
    for offset in 0..<days {
        let day = calendar.date(byAdding: .day, value: offset, to: start)!
        let nextDay = calendar.date(byAdding: .day, value: 1, to: day)!
        result[day] = occurrences.filter { occurrence in
            occurrence.start < nextDay
                && (occurrence.end > day || (occurrence.start == occurrence.end && occurrence.start >= day))
        }
    }
    return result
}
```

To label the days, compare with the day's range: the first day contains `start`, the last day
contains `end`, and the days in between are "all day".

## Cancellation

Parsing and listing occurrences have throwing variants that take an `isCancelled` closure. It is
called for every line, event and recurrence step, and the call throws `CancellationError` as soon
as it returns `true`. The variants without the closure are unchanged.

In a task, pass `Task.isCancelled`:

```swift
let task = Task.detached(priority: .utility) {
    let parser = ICParser(timeZoneHandling: .legacy)
    guard let calendar = try parser.calendar(from: rawICS, isCancelled: { Task.isCancelled }) else {
        return [ICOccurrence]()
    }
    return try calendar.occurrences(from: start, to: end) { Task.isCancelled }
}

// Later, for example when the screen changes:
task.cancel()

do {
    show(try await task.value)
} catch is CancellationError {
    // Stopped early
}
```

The closure works with any other flag too, such as `{ operation.isCancelled }` inside an
`Operation`, or your own thread-safe flag.

A cancelled parse or search stops within a few tens of milliseconds, even for a 30 MB file.

## Concurrency

All model types (`ICalendar`, `ICEvent`, `ICOccurrence`, `ICParser` and the rest) are `Sendable`,
so parsing can run off the main thread and the results can be passed back:

```swift
let calendar = await Task.detached(priority: .utility) {
    ICParser(timeZoneHandling: .legacy).calendar(from: rawICS)
}.value
```

## Identity and equality

- `event1 == event2` compares the `UID` only. A recurring event and the events that change single
  occurrences of it share a `UID`, so they are equal.
- `event.id` is the `UID` plus the `RECURRENCE-ID`, and tells them apart. Use it for `Identifiable`
  lists and to find an event again after reloading a calendar.
- An occurrence is identified by its event's `UID` and its `originalStart`, which stays the same
  when the occurrence is moved. For SwiftUI lists:

```swift
extension ICOccurrence {
    var listID: String {
        "\(event.uid)|\(originalStart.timeIntervalSince1970)"
    }
}

ForEach(occurrences, id: \.listID) { occurrence in
    Text(occurrence.event.summary ?? "")
}
```

## Migrating from 0.3.0

1. Update the minimum deployment target to iOS 15 or tvOS 15 if it is lower.
2. Create the parser with `ICParser(timeZoneHandling: .legacy)` to keep the dates you get today.
3. Replace your own recurrence expansion with `calendar.occurrences(from:to:)`, called once for the
   whole range. It handles `EXDATE`, moved and cancelled occurrences, and monthly rules such as
   "2nd Tuesday".
4. Remove any code that unescapes `\n`, `\,` or `\;` in `summary`, `description` or `location`;
   the parser now does it.
5. Dates that do not exist, such as `20240230`, are now rejected and come back as `nil`.
6. In `.standard` mode, `calendar.timeZones` is now filled in, and times without a time zone are
   device-local instead of UTC.
