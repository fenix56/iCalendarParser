import Foundation

/// A single occurrence of an event, with its start and end.
public struct ICOccurrence: Equatable {

    /// The event this occurrence belongs to. For a moved or changed occurrence this is the
    /// overriding event (the one with `recurrenceId`), with its own summary, location and so on.
    public let event: ICEvent

    public let start: Date

    public let end: Date

    /// The start of this occurrence in the recurring series before it was moved.
    ///
    /// Equal to `start` unless the occurrence was moved by an event with `recurrenceId`.
    public let originalStart: Date

    /// `true` when the event's `DTSTART` is a `DATE` value
    public var isAllDay: Bool {
        event.dtStart?.type == .date
    }

    public init(event: ICEvent, start: Date, end: Date, originalStart: Date) {
        self.event = event
        self.start = start
        self.end = end
        self.originalStart = originalStart
    }
}

// MARK: - Calendar

extension ICalendar {

    /// Returns the occurrences of all events that overlap `start..<end`, sorted by start.
    ///
    /// - Recurring events are expanded from `RRULE` and `RDATE`, without the dates in `EXDATE`.
    /// - An event with `RECURRENCE-ID` replaces the occurrence of the recurring event with the
    ///   same `UID` that originally started at that time, whether or not it was moved into the range.
    /// - An occurrence that started before `start` and is still in progress is included.
    /// - Events with `STATUS:CANCELLED`, and occurrences replaced by one, are skipped unless
    ///   `includeCancelled` is `true`.
    ///
    /// Recurrences are expanded in the time zone of each event's `DTSTART`, so an event at
    /// 10:00 stays at 10:00 local time across daylight saving transitions.
    public func occurrences(
        from start: Date,
        to end: Date,
        includeCancelled: Bool = false
    ) -> [ICOccurrence] {
        guard start < end else {
            return []
        }

        let series = events.filter { $0.recurrenceId == nil }
        let overrides = events.filter { $0.recurrenceId != nil }
        let overridesByUID = Dictionary(grouping: overrides, by: \.uid)
        let cancelledSeries = Set(series.filter(\.isCancelled).map(\.uid))

        let seriesOccurrences = series
            .filter { includeCancelled || !$0.isCancelled }
            .flatMap { event in
                event.occurrences(
                    from: start,
                    to: end,
                    replacedBy: overridesByUID[event.uid]?.compactMap(\.recurrenceId) ?? []
                )
            }

        let overrideOccurrences = overrides
            .filter { includeCancelled || (!$0.isCancelled && !cancelledSeries.contains($0.uid)) }
            .compactMap { $0.overrideOccurrence(from: start, to: end) }

        return (seriesOccurrences + overrideOccurrences).sorted {
            ($0.start, $0.end) < ($1.start, $1.end)
        }
    }
}

// MARK: - Event

extension ICEvent {

    /// `true` when `STATUS` is `CANCELLED`
    public var isCancelled: Bool {
        status?.uppercased() == "CANCELLED"
    }

    /// Returns the occurrences of this event that overlap `start..<end`, sorted by start.
    ///
    /// Expands `RRULE` and `RDATE` and skips `EXDATE`. Overrides in other events
    /// (`RECURRENCE-ID`) are not applied; use `ICalendar.occurrences(from:to:includeCancelled:)` for that.
    public func occurrences(from start: Date, to end: Date) -> [ICOccurrence] {
        occurrences(from: start, to: end, replacedBy: [])
    }

    func occurrences(from start: Date, to end: Date, replacedBy overrides: [ICDateTime]) -> [ICOccurrence] {
        guard let dtStart, start < end else {
            return []
        }

        let zone = dtStart.resolvedZone
        let span = OccurrenceSpan(event: self, dtStart: dtStart)
        let excluded = exceptionDates + overrides

        return seriesStarts(from: start, to: end, zone: zone, span: span)
            .compactMap { wallClock -> ICOccurrence? in
                let occurrenceStart = zone.date(for: wallClock)
                guard !excluded.contains(where: { matches($0, wallClock: wallClock, date: occurrenceStart) }) else {
                    return nil
                }
                let occurrenceEnd = span.end(from: wallClock, start: occurrenceStart, zone: zone)
                guard Self.overlaps(occurrenceStart, occurrenceEnd, start, end) else {
                    return nil
                }
                return ICOccurrence(
                    event: self,
                    start: occurrenceStart,
                    end: occurrenceEnd,
                    originalStart: occurrenceStart
                )
            }
    }

    /// The occurrence of an event that overrides one occurrence of a series
    func overrideOccurrence(from start: Date, to end: Date) -> ICOccurrence? {
        guard let recurrenceId else {
            return nil
        }

        let occurrenceStart = dtStart ?? recurrenceId

        let zone = occurrenceStart.resolvedZone
        let wallClock = zone.wallClock(for: occurrenceStart.date)
        let span = OccurrenceSpan(event: self, dtStart: occurrenceStart)
        let occurrenceEnd = span.end(from: wallClock, start: occurrenceStart.date, zone: zone)

        guard Self.overlaps(occurrenceStart.date, occurrenceEnd, start, end) else {
            return nil
        }

        return ICOccurrence(
            event: self,
            start: occurrenceStart.date,
            end: occurrenceEnd,
            originalStart: recurrenceId.date
        )
    }

    // MARK: - Private

    /// Wall-clock starts of the series from `RRULE`, `RDATE` and `DTSTART`, in order and without duplicates
    private func seriesStarts(from start: Date, to end: Date, zone: DateTimeZone, span: OccurrenceSpan) -> [WallClock] {
        guard let dtStart else {
            return []
        }

        let startWall = zone.wallClock(for: dtStart.date)
        var starts = [startWall]

        if let recurrenceRule {
            // Margins cover offset changes and occurrences that started earlier and are still in progress
            let limit = zone.wallClock(for: end).adding(days: 2)
            let skipBefore = zone.wallClock(for: start).adding(days: -2, seconds: -span.maximumSeconds)
            let until = recurrenceRule.until.map { untilWallClock($0, zone: zone) }

            starts = []
            RecurrenceExpander(rule: recurrenceRule, start: startWall)
                .forEachStart(skipBefore: skipBefore, limit: limit, until: until) { starts.append($0) }
        }

        starts += recurrenceDates.map { recurrenceDate in
            if recurrenceDate.type == .date, dtStart.type == .dateTime {
                // A DATE in RDATE of a timed event keeps the event's time of day
                return WallClock(seconds: recurrenceDate.wallClock.daysSince1970 * WallClock.secondsPerDay)
                    .adding(seconds: startWall.secondsOfDay)
            }
            return zone.wallClock(for: recurrenceDate.date)
        }

        return Set(starts).sorted()
    }

    /// `UNTIL` as an inclusive wall-clock time in the event's zone; a `DATE` includes the whole day
    private func untilWallClock(_ until: ICDateTime, zone: DateTimeZone) -> WallClock {
        guard until.type == .date else {
            return zone.wallClock(for: until.date)
        }
        return WallClock(seconds: until.wallClock.daysSince1970 * WallClock.secondsPerDay)
            .adding(days: 1, seconds: -1)
    }

    /// Whether an `EXDATE` or `RECURRENCE-ID` value refers to the occurrence starting at `date`
    private func matches(_ value: ICDateTime, wallClock: WallClock, date: Date) -> Bool {
        if value.type == .date || dtStart?.type == .date {
            return value.wallClock.daysSince1970 == wallClock.daysSince1970
        }
        return value.date == date
    }

    private static func overlaps(_ start: Date, _ end: Date, _ rangeStart: Date, _ rangeEnd: Date) -> Bool {
        guard start < rangeEnd else {
            return false
        }
        return start == end ? start >= rangeStart : end > rangeStart
    }
}

// MARK: - Span

/// The length of each occurrence, from `DTEND` or `DURATION`
private struct OccurrenceSpan {

    private let isAllDay: Bool
    private let days: Int
    private let seconds: Int

    init(event: ICEvent, dtStart: ICDateTime) {
        isAllDay = dtStart.type == .date

        if let dtEnd = event.dtEnd {
            if isAllDay {
                days = dtEnd.wallClock.daysSince1970 - dtStart.wallClock.daysSince1970
                seconds = 0
            } else {
                days = 0
                seconds = Int(dtEnd.date.timeIntervalSince(dtStart.date))
            }
        } else if let duration = event.duration {
            days = duration.nominalDays
            seconds = duration.exactSeconds
        } else {
            // Without DTEND or DURATION an all-day event lasts one day and a timed event has no length
            days = isAllDay ? 1 : 0
            seconds = 0
        }
    }

    /// An upper bound for the length in seconds
    var maximumSeconds: Int {
        max(0, days * WallClock.secondsPerDay + seconds) + WallClock.secondsPerDay
    }

    func end(from wallClock: WallClock, start: Date, zone: DateTimeZone) -> Date {
        let end = days == 0
            ? start.addingTimeInterval(TimeInterval(seconds))
            : zone.date(for: wallClock.adding(days: days)).addingTimeInterval(TimeInterval(seconds))
        return max(start, end)
    }
}
