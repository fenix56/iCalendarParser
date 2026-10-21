import Foundation

enum TimeZoneResolver {

    /// Returns a system time zone for a `TZID` parameter value.
    ///
    /// Accepts IANA identifiers (`Europe/Berlin`) and identifiers with a vendor
    /// prefix that end with one (`/mozilla.org/20050126_1/Europe/Berlin`).
    static func timeZone(for tzId: String) -> TimeZone? {
        if let timeZone = TimeZone(identifier: tzId) {
            return timeZone
        }

        let components = tzId.split(separator: "/")
        guard components.count > 2 else {
            return nil
        }

        // Try the longest suffix of at least two components first, e.g.
        // "America/Argentina/Buenos_Aires" before "Argentina/Buenos_Aires"
        for start in 1...(components.count - 2) {
            let candidate = components[start...].joined(separator: "/")
            if let timeZone = TimeZone(identifier: candidate) {
                return timeZone
            }
        }

        return nil
    }
}

/// Resolves the `TZID` values of one calendar while it is parsed, looking up each identifier once
final class TimeZoneLookup {

    let handling: ICParser.TimeZoneHandling
    private let definitions: [ICTimeZone]
    private var zones = [String: DateTimeZone?]()

    init(definitions: [ICTimeZone] = [], handling: ICParser.TimeZoneHandling = .standard) {
        self.definitions = definitions
        self.handling = handling
    }

    /// A system time zone for the identifier, or else its `VTIMEZONE` definition; nil when there is neither
    func zone(for tzId: String) -> DateTimeZone? {
        if let zone = zones[tzId] {
            return zone
        }
        let zone = resolve(tzId)
        zones[tzId] = .some(zone)
        return zone
    }

    private func resolve(_ tzId: String) -> DateTimeZone? {
        let timeZone = handling == .legacy
            ? TimeZone(identifier: tzId)
            : TimeZoneResolver.timeZone(for: tzId)

        if let timeZone {
            return .system(timeZone)
        }

        guard
            handling == .standard,
            let definition = definitions.first(where: { $0.timeZoneId == tzId }),
            definition.offset(at: Date(timeIntervalSince1970: 0)) != nil
        else { return nil }

        return .definition(definition)
    }
}

// MARK: - VTIMEZONE evaluation

// The observance in effect is the `STANDARD` or `DAYLIGHT` one with the latest onset; before all of them,
// `TZOFFSETFROM` of the first one applies. Yearly rules with `BYMONTH` and `BYDAY` or `BYMONTHDAY` are
// supported; an observance with any other rule counts as starting once at its `DTSTART`.
extension ICTimeZone {

    /// An observance with its offsets in seconds
    private struct Observance {
        let observance: ICSubTimeZone
        let offsetFrom: Int
        let offsetTo: Int
    }

    /// Returns the UTC offset in seconds in effect at `date`, or nil when no observance has valid offsets
    func offset(at date: Date) -> Int? {
        let observances = observancesWithOffsets

        // An onset is a wall-clock time in the offset before it
        let latest = observances
            .compactMap { item -> (onset: Date, offset: Int)? in
                item.observance
                    .latestOnset(onOrBefore: WallClock(date: date, offset: item.offsetFrom))
                    .map { ($0.date(offset: item.offsetFrom), item.offsetTo) }
            }
            .max { $0.onset < $1.onset }

        return latest?.offset ?? Self.offsetBeforeFirst(of: observances)
    }

    /// Returns the instant of a wall-clock time, or nil when no observance has valid offsets.
    ///
    /// Gives the same result as `wallClock.date(offsetAt: offset(at:))` in one pass over the observances:
    /// a time that occurs twice is its first occurrence, and a skipped time is read with the offset before the gap.
    func date(for wallClock: WallClock) -> Date? {
        let observances = observancesWithOffsets

        let latest = observances
            .compactMap { item -> (onset: WallClock, item: Observance)? in
                item.observance.latestOnset(onOrBefore: wallClock).map { ($0, item) }
            }
            .max { $0.onset < $1.onset }

        guard let latest else {
            return Self.offsetBeforeFirst(of: observances).map { wallClock.date(offset: $0) }
        }

        // Clocks go forward from the onset to the onset plus the change in offset; a time repeated when
        // they go back is before the onset, so it falls to the previous observance
        let offsetFrom = latest.item.offsetFrom
        let offsetTo = latest.item.offsetTo
        let isSkipped = wallClock.seconds < latest.onset.seconds + offsetTo - offsetFrom
        return wallClock.date(offset: isSkipped ? offsetFrom : offsetTo)
    }

    private var observancesWithOffsets: [Observance] {
        (standardObservances + daylightObservances).compactMap { observance in
            guard
                let offsetFrom = UTCOffset.seconds(from: observance.timeZoneOffsetFrom),
                let offsetTo = UTCOffset.seconds(from: observance.timeZoneOffsetTo)
            else { return nil }
            return Observance(observance: observance, offsetFrom: offsetFrom, offsetTo: offsetTo)
        }
    }

    private static func offsetBeforeFirst(of observances: [Observance]) -> Int? {
        observances.min { $0.observance.dtStart < $1.observance.dtStart }?.offsetFrom
    }
}

extension ICSubTimeZone {

    /// The wall-clock time of `DTSTART`, which is local time in the offset in use before this observance
    var wallClockStart: WallClock? {
        UTCOffset.seconds(from: timeZoneOffsetFrom).map { WallClock(date: dtStart, offset: $0) }
    }

    /// Returns the latest onset of this observance at or before the given wall-clock time
    func latestOnset(onOrBefore target: WallClock) -> WallClock? {
        guard let start = wallClockStart, start <= target else {
            return nil
        }

        guard
            let rule = recurrenceRule,
            rule.frequency == .yearly,
            let month = rule.byMonth?.first
        else { return start }

        let until = rule.until.map { WallClock(date: $0.date, offset: 0) }

        var year = min(target.year, until?.year ?? target.year)
        while year >= start.year {
            if let onset = onset(in: year, month: month, rule: rule, start: start),
               onset <= target,
               onset >= start,
               until.map({ onset <= $0 }) ?? true {
                return onset
            }
            year -= 1
        }

        return start
    }

    private func onset(
        in year: Int,
        month: Int,
        rule: ICRRule,
        start: WallClock
    ) -> WallClock? {
        let lastDay = WallClock.daysInMonth(year: year, month: month)
        let byDay = rule.byDay?.first
        let day: Int?

        if let monthDays = rule.byDayOfMonth, !monthDays.isEmpty {
            // e.g. BYMONTHDAY=8,9,10,11,12,13,14;BYDAY=SU for "second Sunday"
            day = monthDays
                .map { $0 > 0 ? $0 : lastDay + $0 + 1 }
                .filter { (1...lastDay).contains($0) }
                .sorted()
                .first { monthDay in
                    guard let byDay else { return true }
                    let weekday = WallClock(year: year, month: month, day: monthDay).weekday
                    return weekday == byDay.dayOfWeek.weekday
                }
        } else if let byDay {
            day = Self.day(of: byDay, year: year, month: month, lastDay: lastDay)
        } else {
            day = min(start.day, lastDay)
        }

        guard let day else {
            return nil
        }

        return WallClock(year: year, month: month, day: day, secondsOfDay: start.secondsOfDay)
    }

    /// Returns the day of the month for a `BYDAY` value such as `2SU` or `-1SU`
    private static func day(
        of byDay: ICRRule.Day,
        year: Int,
        month: Int,
        lastDay: Int
    ) -> Int? {
        let week = byDay.week ?? 1
        let weekday = byDay.dayOfWeek.weekday

        if week > 0 {
            let firstWeekday = WallClock(year: year, month: month, day: 1).weekday
            let day = 1 + (weekday - firstWeekday + 7) % 7 + (week - 1) * 7
            return day <= lastDay ? day : nil
        }

        let lastWeekday = WallClock(year: year, month: month, day: lastDay).weekday
        let day = lastDay - (lastWeekday - weekday + 7) % 7 + (week + 1) * 7
        return day >= 1 ? day : nil
    }
}
