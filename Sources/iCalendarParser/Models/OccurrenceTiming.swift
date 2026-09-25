import Foundation

// MARK: - Future changes

/// An event with `RANGE=THISANDFUTURE`, prepared for applying to later occurrences of its series
struct FutureChange {

    let override: ICEvent

    /// The original start of the occurrence the change begins with
    let originalStart: Date

    /// How far the change moved its occurrence, in wall-clock seconds of the series' zone
    let shift: Int

    let span: OccurrenceSpan

    init?(override: ICEvent, zone: DateTimeZone, seriesSpan: OccurrenceSpan) {
        guard let recurrenceId = override.recurrenceId else {
            return nil
        }

        self.override = override
        originalStart = recurrenceId.date

        let newStart = override.dtStart ?? recurrenceId
        shift = zone.wallClock(for: newStart.date).seconds - zone.wallClock(for: recurrenceId.date).seconds

        // Without its own DTEND or DURATION, the change keeps the length of the series
        span = override.dtEnd == nil && override.duration == nil
            ? seriesSpan
            : OccurrenceSpan(event: override, dtStart: newStart)
    }
}

// MARK: - Span

/// The length of each occurrence, from `DTEND` or `DURATION`
struct OccurrenceSpan {

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
