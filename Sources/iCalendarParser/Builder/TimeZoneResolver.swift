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

// MARK: - VTIMEZONE evaluation

extension ICTimeZone {

    /// Returns the instant of a wall-clock time in this time zone definition.
    ///
    /// Uses the `STANDARD` or `DAYLIGHT` observance with the latest onset before the
    /// given time. Yearly rules with `BYMONTH` and `BYDAY` or `BYMONTHDAY` are supported;
    /// an observance with any other rule counts as starting once at its `DTSTART`.
    func date(for wallClock: WallClock) -> Date? {
        let observances = [standard, daylight].compactMap { $0 }

        let latest = observances
            .compactMap { observance -> (onset: WallClock, offset: Int)? in
                guard
                    let offset = UTCOffset.seconds(from: observance.timeZoneOffsetTo),
                    let onset = observance.latestOnset(onOrBefore: wallClock)
                else { return nil }
                return (onset, offset)
            }
            .max { $0.onset < $1.onset }

        if let latest {
            return wallClock.date(offset: latest.offset)
        }

        // The time is before every observance: use the offset in effect before the first one
        guard
            let earliest = observances.min(by: { $0.dtStart < $1.dtStart }),
            let offset = UTCOffset.seconds(from: earliest.timeZoneOffsetFrom)
        else { return nil }

        return wallClock.date(offset: offset)
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

        var year = target.year
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
