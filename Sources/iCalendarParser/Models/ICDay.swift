import Foundation

/// The occurrences on one calendar day, from `ICalendar.occurrencesByDay(from:days:calendar:includeCancelled:)`
public struct ICDay: Equatable, Sendable {

    /// The start of the day: midnight in the time zone of the calendar used
    public let date: Date

    /// The occurrences that overlap the day, sorted by start.
    ///
    /// An occurrence that lasts several days is listed on each of them.
    public let occurrences: [ICDayOccurrence]

    public init(date: Date, occurrences: [ICDayOccurrence]) {
        self.date = date
        self.occurrences = occurrences
    }
}

/// An occurrence as it appears on one day
public struct ICDayOccurrence: Equatable, Sendable {

    /// Which part of an occurrence falls on a day
    public enum Part: Equatable, Sendable {

        /// Starts and ends on this day
        case whole

        /// Starts on this day and continues on the next
        case start

        /// Started on an earlier day and continues on the next
        case middle

        /// Started on an earlier day and ends on this day
        case end
    }

    public let occurrence: ICOccurrence

    /// Which part of the occurrence falls on this day
    public let part: Part

    /// Which day of the occurrence this is, from 1, as in "day 2 of 3"
    public let dayNumber: Int

    /// The number of days the occurrence spans
    public let dayCount: Int

    public init(occurrence: ICOccurrence, part: Part, dayNumber: Int, dayCount: Int) {
        self.occurrence = occurrence
        self.part = part
        self.dayNumber = dayNumber
        self.dayCount = dayCount
    }
}

// MARK: - Calendar

extension ICalendar {

    /// Returns the occurrences on each of `days` calendar days, starting with the day of `start`.
    ///
    /// - The first day begins at `start`, so passing the current time leaves out occurrences that
    ///   already ended today. The other days begin at midnight.
    /// - Every day is returned, also days without occurrences.
    /// - An occurrence that lasts several days is listed on each of them, with the part of it that
    ///   falls on that day.
    /// - Days follow `calendar`. All-day events start at midnight in the device's time zone, so use
    ///   a calendar in that time zone, such as `Calendar.current`.
    ///
    /// ```swift
    /// let today = calendar.occurrencesByDay(from: Date(), days: 1)
    /// let week = calendar.occurrencesByDay(from: startOfTomorrow, days: 6)
    /// ```
    public func occurrencesByDay(
        from start: Date,
        days: Int,
        calendar: Calendar = .current,
        includeCancelled: Bool = false
    ) -> [ICDay] {
        occurrencesByDay(
            from: start,
            days: days,
            calendar: calendar,
            includeCancelled: includeCancelled,
            checkCancellation: {}
        )
    }

    /// Returns the occurrences on each of `days` calendar days, starting with the day of `start`.
    ///
    /// Works like `occurrencesByDay(from:days:calendar:includeCancelled:)`, and calls `isCancelled`
    /// regularly. Throws `CancellationError` as soon as it returns `true`.
    public func occurrencesByDay(
        from start: Date,
        days: Int,
        calendar: Calendar = .current,
        includeCancelled: Bool = false,
        isCancelled: () -> Bool
    ) throws -> [ICDay] {
        try occurrencesByDay(from: start, days: days, calendar: calendar, includeCancelled: includeCancelled) {
            try throwIfCancelled(isCancelled)
        }
    }

    private func occurrencesByDay(
        from start: Date,
        days: Int,
        calendar: Calendar,
        includeCancelled: Bool,
        checkCancellation: () throws -> Void
    ) rethrows -> [ICDay] {
        guard days > 0, let dayStarts = Self.dayStarts(from: start, days: days, calendar: calendar) else {
            return []
        }

        let occurrences = try occurrences(
            from: start,
            to: dayStarts[days],
            includeCancelled: includeCancelled,
            checkCancellation: checkCancellation
        )

        var occurrencesOfDay = Array(repeating: [ICDayOccurrence](), count: days)
        for occurrence in occurrences {
            try checkCancellation()

            for index in 0..<days {
                // The first day begins at `start`, the others at midnight
                let rangeStart = index == 0 ? start : dayStarts[index]
                let rangeEnd = dayStarts[index + 1]

                if occurrence.start >= rangeEnd {
                    continue
                }
                if occurrence.start < rangeStart, occurrence.end <= rangeStart {
                    break
                }
                guard ICEvent.overlaps(occurrence.start, occurrence.end, rangeStart, rangeEnd) else {
                    continue
                }

                occurrencesOfDay[index].append(
                    Self.dayOccurrence(occurrence, dayStart: dayStarts[index], dayEnd: rangeEnd, calendar: calendar)
                )
            }
        }

        return (0..<days).map { ICDay(date: dayStarts[$0], occurrences: occurrencesOfDay[$0]) }
    }

    /// Midnight of the day of `start` and of each following day, including the end of the last day
    private static func dayStarts(from start: Date, days: Int, calendar: Calendar) -> [Date]? {
        var dayStarts = [calendar.startOfDay(for: start)]
        for index in 0..<days {
            guard let next = calendar.date(byAdding: .day, value: 1, to: dayStarts[index]) else {
                return nil
            }
            dayStarts.append(next)
        }
        return dayStarts
    }

    private static func dayOccurrence(
        _ occurrence: ICOccurrence,
        dayStart: Date,
        dayEnd: Date,
        calendar: Calendar
    ) -> ICDayOccurrence {
        let startsOnDay = occurrence.start >= dayStart
        let endsOnDay = occurrence.end <= dayEnd

        let part: ICDayOccurrence.Part
        switch (startsOnDay, endsOnDay) {
        case (true, true): part = .whole
        case (true, false): part = .start
        case (false, false): part = .middle
        case (false, true): part = .end
        }

        guard part != .whole else {
            return ICDayOccurrence(occurrence: occurrence, part: part, dayNumber: 1, dayCount: 1)
        }

        // An occurrence that ends exactly at midnight does not extend into that day
        let firstDay = calendar.startOfDay(for: occurrence.start)
        var lastDay = calendar.startOfDay(for: occurrence.end)
        if lastDay == occurrence.end, occurrence.end > occurrence.start {
            lastDay = calendar.date(byAdding: .day, value: -1, to: lastDay) ?? lastDay
        }

        let dayNumber = (calendar.dateComponents([.day], from: firstDay, to: dayStart).day ?? 0) + 1
        let dayCount = (calendar.dateComponents([.day], from: firstDay, to: lastDay).day ?? 0) + 1
        return ICDayOccurrence(occurrence: occurrence, part: part, dayNumber: dayNumber, dayCount: dayCount)
    }
}
