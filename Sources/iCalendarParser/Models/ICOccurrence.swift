import Foundation

/// A single occurrence of an event, with its start and end.
public struct ICOccurrence: Equatable, Sendable {

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
    ///   With `RANGE=THISANDFUTURE` it also changes every later occurrence: they take its properties
    ///   and length, and move by as much as it moved.
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
        occurrences(from: start, to: end, includeCancelled: includeCancelled, checkCancellation: {})
    }

    /// Returns the occurrences of all events that overlap `start..<end`, sorted by start.
    ///
    /// Works like `occurrences(from:to:includeCancelled:)`, and calls `isCancelled` regularly
    /// while expanding recurring events. Throws `CancellationError` as soon as it returns `true`.
    /// Inside a task, pass `{ Task.isCancelled }`:
    ///
    /// ```swift
    /// let upcoming = try calendar.occurrences(from: start, to: end) { Task.isCancelled }
    /// ```
    public func occurrences(
        from start: Date,
        to end: Date,
        includeCancelled: Bool = false,
        isCancelled: () -> Bool
    ) throws -> [ICOccurrence] {
        try occurrences(from: start, to: end, includeCancelled: includeCancelled) {
            if isCancelled() {
                throw CancellationError()
            }
        }
    }

    private func occurrences(
        from start: Date,
        to end: Date,
        includeCancelled: Bool,
        checkCancellation: () throws -> Void
    ) rethrows -> [ICOccurrence] {
        guard start < end else {
            return []
        }

        // One pass to collect overrides by UID and cancelled series, without copying events
        var overridesByUID = [String: [ICDateTime]]()
        var futureOverridesByUID = [String: [ICEvent]]()
        var cancelledSeries = Set<String>()
        for event in events {
            try checkCancellation()
            if let recurrenceId = event.recurrenceId {
                overridesByUID[event.uid, default: []].append(recurrenceId)
                if event.appliesToFutureOccurrences {
                    futureOverridesByUID[event.uid, default: []].append(event)
                }
            } else if event.isCancelled {
                cancelledSeries.insert(event.uid)
            }
        }

        var occurrences = [ICOccurrence]()
        for event in events {
            try checkCancellation()
            if event.recurrenceId == nil {
                guard includeCancelled || !event.isCancelled else {
                    continue
                }
                let seriesOverrides = SeriesOverrides(
                    replaced: overridesByUID[event.uid] ?? [],
                    future: futureOverridesByUID[event.uid] ?? [],
                    includeCancelled: includeCancelled
                )
                occurrences += try event.occurrences(
                    from: start,
                    to: end,
                    overrides: seriesOverrides,
                    checkCancellation: checkCancellation
                )
            } else if includeCancelled || (!event.isCancelled && !cancelledSeries.contains(event.uid)),
                      let occurrence = event.overrideOccurrence(from: start, to: end) {
                occurrences.append(occurrence)
            }
        }

        // Sort indices rather than occurrences, which are large values; the index keeps the order stable
        try checkCancellation()
        let order = occurrences.indices.sorted { lhs, rhs in
            (occurrences[lhs].start, occurrences[lhs].end, lhs) < (occurrences[rhs].start, occurrences[rhs].end, rhs)
        }
        try checkCancellation()
        return order.map { occurrences[$0] }
    }
}

// MARK: - Event

/// The other events of a recurring event's `UID` that change its occurrences
struct SeriesOverrides {

    /// `RECURRENCE-ID` values of all events that replace an occurrence
    let replaced: [ICDateTime]

    /// Events with `RANGE=THISANDFUTURE`, which also change later occurrences
    let future: [ICEvent]

    /// Whether occurrences cancelled by a future change are kept
    let includeCancelled: Bool

    static let empty = SeriesOverrides(replaced: [], future: [], includeCancelled: true)
}

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
        occurrences(from: start, to: end, overrides: .empty, checkCancellation: {})
    }

    /// Returns the occurrences of this event that overlap `start..<end`, sorted by start.
    ///
    /// Works like `occurrences(from:to:)`, and calls `isCancelled` regularly while expanding.
    /// Throws `CancellationError` as soon as it returns `true`.
    public func occurrences(from start: Date, to end: Date, isCancelled: () -> Bool) throws -> [ICOccurrence] {
        try occurrences(from: start, to: end, overrides: .empty) {
            if isCancelled() {
                throw CancellationError()
            }
        }
    }

    func occurrences(
        from start: Date,
        to end: Date,
        overrides: SeriesOverrides,
        checkCancellation: () throws -> Void
    ) rethrows -> [ICOccurrence] {
        try checkCancellation()

        guard let dtStart, start < end else {
            return []
        }

        let zone = dtStart.resolvedZone
        let span = OccurrenceSpan(event: self, dtStart: dtStart)
        let excluded = exceptionDates + overrides.replaced
        let changes = overrides.future
            .compactMap { FutureChange(override: $0, zone: zone, seriesSpan: span) }
            .sorted { $0.originalStart < $1.originalStart }

        // Later occurrences may move into or out of the range by as much as a change moved them
        let margin = TimeInterval(changes.map { abs($0.shift) + $0.span.maximumSeconds }.max() ?? 0)
        let starts = try seriesStarts(
            from: start.addingTimeInterval(-margin),
            to: end.addingTimeInterval(margin),
            zone: zone,
            span: span,
            checkCancellation: checkCancellation
        )

        return try starts.compactMap { wallClock -> ICOccurrence? in
            try checkCancellation()
            let originalStart = zone.date(for: wallClock)
            guard !excluded.contains(where: { matches($0, wallClock: wallClock, date: originalStart) }) else {
                return nil
            }

            // The latest change at or before this occurrence applies to it
            let change = changes.last { $0.originalStart <= originalStart }
            if let change, change.override.isCancelled, !overrides.includeCancelled {
                return nil
            }

            let shiftedWallClock = wallClock.adding(seconds: change?.shift ?? 0)
            let occurrenceStart = change == nil ? originalStart : zone.date(for: shiftedWallClock)
            let occurrenceEnd = (change?.span ?? span).end(from: shiftedWallClock, start: occurrenceStart, zone: zone)
            guard Self.overlaps(occurrenceStart, occurrenceEnd, start, end) else {
                return nil
            }

            return ICOccurrence(
                event: change?.override ?? self,
                start: occurrenceStart,
                end: occurrenceEnd,
                originalStart: originalStart
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
    private func seriesStarts(
        from start: Date,
        to end: Date,
        zone: DateTimeZone,
        span: OccurrenceSpan,
        checkCancellation: () throws -> Void
    ) rethrows -> [WallClock] {
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
            try RecurrenceExpander(rule: recurrenceRule, start: startWall).forEachStart(
                skipBefore: skipBefore,
                limit: limit,
                until: until,
                checkCancellation: checkCancellation
            ) { starts.append($0) }
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
