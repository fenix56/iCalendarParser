import Foundation

/// Expands a recurrence rule into wall-clock start times.
///
/// Supports every frequency and rule part of RFC 5545: `INTERVAL`, `COUNT`, `UNTIL`, `BYMONTH`,
/// `BYWEEKNO`, `BYYEARDAY`, `BYMONTHDAY`, `BYDAY` (with ordinals such as `2TU` or `-1SU` for
/// monthly and yearly rules), `BYHOUR`, `BYMINUTE`, `BYSECOND`, `BYSETPOS` and `WKST`.
///
/// See more in [RFC 5545](
/// https://www.rfc-editor.org/rfc/rfc5545#section-3.3.10)
struct RecurrenceExpander {

    /// Stops runaway rules (e.g. `FREQ=SECONDLY` over years with a large `COUNT`)
    static let maximumPeriods = 1_000_000

    private struct DayRule {
        let week: Int?
        let weekday: Int
    }

    private struct Period {
        let start: WallClock
        let year: Int
        let days: Range<Int>
    }

    private let frequency: ICRRule.Frequency
    private let interval: Int
    private let count: Int?
    private let start: WallClock
    private let weekStart: Int
    private let byMonth: [Int]?
    private let byWeekNo: [Int]?
    private let byYearDay: [Int]?
    private let byMonthDay: [Int]?
    private let byDay: [DayRule]?
    private let byHour: [Int]?
    private let byMinute: [Int]?
    private let bySecond: [Int]?
    private let bySetPos: [Int]?

    init(rule: ICRRule, start: WallClock) {
        func nonEmpty<T>(_ values: [T]?) -> [T]? {
            values?.isEmpty == false ? values : nil
        }

        frequency = rule.frequency
        interval = max(1, rule.interval ?? 1)
        count = rule.count
        self.start = start
        weekStart = rule.startOfWorkweek?.weekday ?? ICRRule.DayOfWeek.monday.weekday
        byWeekNo = nonEmpty(rule.byWeekOfYear)
        byYearDay = nonEmpty(rule.byDayOfYear)
        byHour = nonEmpty(rule.byHour)
        byMinute = nonEmpty(rule.byMinute)
        bySecond = nonEmpty(rule.bySecond)
        bySetPos = nonEmpty(rule.bySetPos)

        var byMonth = nonEmpty(rule.byMonth)
        var byMonthDay = nonEmpty(rule.byDayOfMonth)
        var byDay = nonEmpty(rule.byDay)?.map { DayRule(week: $0.week, weekday: $0.dayOfWeek.weekday) }

        // Without a day rule, the day of DTSTART is used
        if byWeekNo == nil, byYearDay == nil, byMonthDay == nil, byDay == nil {
            switch rule.frequency {
            case .yearly:
                byMonth = byMonth ?? [start.month]
                byMonthDay = [start.day]
            case .monthly:
                byMonthDay = [start.day]
            case .weekly:
                byDay = [DayRule(week: nil, weekday: start.weekday)]
            default:
                break
            }
        }

        self.byMonth = byMonth
        self.byMonthDay = byMonthDay
        self.byDay = byDay
    }

    /// Calls `body` with each start time in order, beginning with the start of the series.
    ///
    /// - Parameters:
    ///   - skipBefore: without `COUNT`, periods before this time may be skipped
    ///   - limit: stops after this time
    ///   - until: the inclusive end of the series in wall-clock time (`UNTIL`)
    ///   - checkCancellation: called once per period; throws to stop expanding
    func forEachStart(
        skipBefore: WallClock?,
        limit: WallClock,
        until: WallClock?,
        checkCancellation: () throws -> Void = {},
        _ body: (WallClock) -> Void
    ) rethrows {
        var remaining = count ?? .max
        guard remaining > 0, start <= limit, until.map({ start <= $0 }) ?? true else {
            return
        }

        // DTSTART is always the first occurrence
        body(start)
        remaining -= 1

        let firstIndex = firstPeriodIndex(skipBefore: skipBefore)
        for index in firstIndex..<(firstIndex + Self.maximumPeriods) {
            try checkCancellation()

            let period = period(at: index)
            guard remaining > 0, period.start <= limit else {
                return
            }

            for candidate in candidates(in: period) where candidate > start {
                if candidate > limit || until.map({ candidate > $0 }) == true {
                    return
                }
                body(candidate)
                remaining -= 1
                if remaining == 0 {
                    return
                }
            }
        }
    }

    // MARK: - Periods

    private var fixedPeriodLength: Int? {
        switch frequency {
        case .secondly: return 1
        case .minutely: return 60
        case .hourly: return 3_600
        case .daily: return WallClock.secondsPerDay
        case .weekly: return 7 * WallClock.secondsPerDay
        case .monthly, .yearly: return nil
        }
    }

    private func firstPeriodIndex(skipBefore: WallClock?) -> Int {
        guard count == nil, let skipBefore, let length = fixedPeriodLength else {
            return 0
        }
        let distance = skipBefore.seconds - period(at: 0).start.seconds
        return max(0, distance / (length * interval))
    }

    private func period(at index: Int) -> Period {
        switch frequency {
        case .yearly:
            let year = start.year + index * interval
            let days = byWeekNo == nil
                ? WallClock.daysSince1970(year: year, month: 1, day: 1)..<WallClock.daysSince1970(
                    year: year + 1, month: 1, day: 1)
                : weekNumberingYearStart(year)..<weekNumberingYearStart(year + 1)
            return Period(start: WallClock(seconds: days.lowerBound * WallClock.secondsPerDay), year: year, days: days)
        case .monthly:
            let monthIndex = start.year * 12 + start.month - 1 + index * interval
            let year = monthIndex / 12
            let month = monthIndex % 12 + 1
            let first = WallClock.daysSince1970(year: year, month: month, day: 1)
            let days = first..<(first + WallClock.daysInMonth(year: year, month: month))
            return Period(start: WallClock(seconds: first * WallClock.secondsPerDay), year: year, days: days)
        case .weekly:
            let firstWeek = start.daysSince1970 - (start.weekday - weekStart + 7) % 7
            let first = firstWeek + index * 7 * interval
            let periodStart = WallClock(seconds: first * WallClock.secondsPerDay)
            return Period(start: periodStart, year: periodStart.year, days: first..<(first + 7))
        case .daily, .hourly, .minutely, .secondly:
            let length = fixedPeriodLength ?? WallClock.secondsPerDay
            let firstStart = start.seconds - (start.seconds % length + length) % length
            let periodStart = WallClock(seconds: firstStart + index * interval * length)
            let day = periodStart.daysSince1970
            return Period(start: periodStart, year: periodStart.year, days: day..<(day + 1))
        }
    }

    // MARK: - Candidates

    private func candidates(in period: Period) -> [WallClock] {
        let times = timesOfDay(in: period)
        var candidates = [WallClock]()

        for day in period.days where matches(day: day, periodYear: period.year) {
            candidates += times.map { WallClock(seconds: day * WallClock.secondsPerDay + $0) }
        }

        guard let bySetPos else {
            return candidates
        }

        let positions = bySetPos.compactMap { position -> Int? in
            let index = position > 0 ? position - 1 : candidates.count + position
            return candidates.indices.contains(index) ? index : nil
        }
        return Set(positions).sorted().map { candidates[$0] }
    }

    /// Seconds of the day for the occurrences in a period, in order
    private func timesOfDay(in period: Period) -> [Int] {
        // Units at or above the frequency are fixed by the period and only filtered;
        // finer units are expanded from the rule or taken from DTSTART
        let rank: Int
        switch frequency {
        case .secondly: rank = 0
        case .minutely: rank = 1
        case .hourly: rank = 2
        default: rank = 3
        }

        func values(_ unitRank: Int, fixed: Int, rule: [Int]?, default value: Int) -> [Int] {
            if unitRank >= rank {
                return rule.map { $0.contains(fixed) ? [fixed] : [] } ?? [fixed]
            }
            return (rule ?? [value]).sorted()
        }

        let hours = values(2, fixed: period.start.hour, rule: byHour, default: start.hour)
        let minutes = values(1, fixed: period.start.minute, rule: byMinute, default: start.minute)
        let seconds = values(0, fixed: period.start.second, rule: bySecond, default: start.second)

        return hours.flatMap { hour in
            minutes.flatMap { minute in
                seconds.map { second in hour * 3_600 + minute * 60 + min(second, 59) }
            }
        }
    }

    // MARK: - Day rules

    private func matches(day: Int, periodYear: Int) -> Bool {
        let date = WallClock.civilDate(daysSince1970: day)
        let lastDayOfMonth = WallClock.daysInMonth(year: date.year, month: date.month)
        let dayOfYear = day - WallClock.daysSince1970(year: date.year, month: 1, day: 1) + 1
        let daysInYear = WallClock.isLeapYear(date.year) ? 366 : 365

        if let byMonth, !byMonth.contains(date.month) {
            return false
        }
        if let byWeekNo, !matchesWeekNumber(day: day, year: frequency == .yearly ? periodYear : date.year, byWeekNo) {
            return false
        }
        if let byYearDay, !byYearDay.contains(dayOfYear), !byYearDay.contains(dayOfYear - daysInYear - 1) {
            return false
        }
        if let byMonthDay, !byMonthDay.contains(date.day), !byMonthDay.contains(date.day - lastDayOfMonth - 1) {
            return false
        }
        if let byDay {
            // Ordinals count within the month for monthly rules and yearly rules with BYMONTH, otherwise the year
            let inMonth = frequency == .monthly || byMonth != nil
            let position = inMonth ? date.day : dayOfYear
            let length = inMonth ? lastDayOfMonth : daysInYear
            return byDay.contains { matches($0, day: day, position: position, length: length) }
        }
        return true
    }

    private func matches(_ rule: DayRule, day: Int, position: Int, length: Int) -> Bool {
        guard WallClock.weekday(daysSince1970: day) == rule.weekday else {
            return false
        }
        guard let week = rule.week, week != 0, frequency == .monthly || frequency == .yearly else {
            return true
        }
        return week == (position - 1) / 7 + 1 || week == -((length - position) / 7 + 1)
    }

    /// The first day of week 1 of `year`: the first week, starting on WKST, with at least four days in the year
    private func weekNumberingYearStart(_ year: Int) -> Int {
        let firstDay = WallClock.daysSince1970(year: year, month: 1, day: 1)
        let offset = (WallClock.weekday(daysSince1970: firstDay) - weekStart + 7) % 7
        return offset <= 3 ? firstDay - offset : firstDay + 7 - offset
    }

    private func matchesWeekNumber(day: Int, year: Int, _ weeks: [Int]) -> Bool {
        let yearStart = weekNumberingYearStart(year)
        let nextYearStart = weekNumberingYearStart(year + 1)
        guard (yearStart..<nextYearStart).contains(day) else {
            return false
        }
        let week = (day - yearStart) / 7 + 1
        let weeksInYear = (nextYearStart - yearStart) / 7
        return weeks.contains(week) || weeks.contains(week - weeksInYear - 1)
    }
}
