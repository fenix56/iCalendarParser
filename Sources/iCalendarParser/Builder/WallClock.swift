import Foundation

/// A calendar date and time of day without a time zone, as written in an iCalendar value.
///
/// Stored as the number of seconds since `19700101T000000` on the same wall clock,
/// so it can be compared and converted to a `Date` once the UTC offset is known.
struct WallClock: Hashable, Comparable {

    let seconds: Int

    init(seconds: Int) {
        self.seconds = seconds
    }

    init(year: Int, month: Int, day: Int, secondsOfDay: Int = 0) {
        self.seconds = Self.daysSince1970(year: year, month: month, day: day) * Self.secondsPerDay + secondsOfDay
    }

    /// Wall-clock time of `date` in a zone that is `offset` seconds ahead of UTC
    init(date: Date, offset: Int) {
        self.seconds = Int(date.timeIntervalSince1970.rounded(.down)) + offset
    }

    /// Parses a `DATE` (`yyyyMMdd`) or a local `DATE-TIME` (`yyyyMMdd'T'HHmmss`) value.
    ///
    /// Returns nil for any other format or for an invalid date or time.
    ///
    /// See more in [RFC 5545](
    /// https://www.rfc-editor.org/rfc/rfc5545#section-3.3.5)
    init?(_ value: String) {
        let digits = Array(value.utf8)
        let hasTime = digits.count == 15 && digits[8] == UInt8(ascii: "T")
        guard digits.count == 8 || hasTime else {
            return nil
        }

        func number(_ range: Range<Int>) -> Int? {
            var result = 0
            for digit in digits[range] {
                guard (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(digit) else { return nil }
                result = result * 10 + Int(digit - UInt8(ascii: "0"))
            }
            return result
        }

        guard
            let year = number(0..<4),
            let month = number(4..<6),
            let day = number(6..<8),
            (1...12).contains(month),
            (1...Self.daysInMonth(year: year, month: month)).contains(day)
        else { return nil }

        var secondsOfDay = 0
        if hasTime {
            // A leap second (60) is accepted and treated as the 59th second
            guard
                let hour = number(9..<11),
                let minute = number(11..<13),
                let second = number(13..<15),
                hour < 24, minute < 60, second <= 60
            else { return nil }
            secondsOfDay = hour * 3_600 + minute * 60 + min(second, 59)
        }

        self.init(year: year, month: month, day: day, secondsOfDay: secondsOfDay)
    }

    // MARK: - Components

    var daysSince1970: Int {
        // Floor division, so times before 1970 fall on the correct day
        seconds >= 0
            ? seconds / Self.secondsPerDay
            : (seconds - Self.secondsPerDay + 1) / Self.secondsPerDay
    }

    var secondsOfDay: Int {
        seconds - daysSince1970 * Self.secondsPerDay
    }

    var year: Int {
        Self.civilDate(daysSince1970: daysSince1970).year
    }

    var day: Int {
        Self.civilDate(daysSince1970: daysSince1970).day
    }

    var month: Int {
        Self.civilDate(daysSince1970: daysSince1970).month
    }

    var hour: Int {
        secondsOfDay / 3_600
    }

    var minute: Int {
        secondsOfDay % 3_600 / 60
    }

    var second: Int {
        secondsOfDay % 60
    }

    /// Day of the week, 1 (Sunday) to 7 (Saturday), matching `ICRRule.DayOfWeek.weekday`
    var weekday: Int {
        Self.weekday(daysSince1970: daysSince1970)
    }

    static func weekday(daysSince1970 days: Int) -> Int {
        // 1970-01-01 was a Thursday
        ((days % 7 + 7) % 7 + 4) % 7 + 1
    }

    func adding(days: Int = 0, seconds: Int = 0) -> WallClock {
        WallClock(seconds: self.seconds + days * Self.secondsPerDay + seconds)
    }

    // MARK: - Conversion

    /// The instant of this wall-clock time in a zone `offset` seconds ahead of UTC
    func date(offset: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(seconds - offset))
    }

    /// The instant of this wall-clock time in `timeZone`.
    ///
    /// A time skipped by a daylight saving transition resolves to the
    /// same wall-clock time after the transition.
    func date(in timeZone: TimeZone) -> Date {
        let asUTC = date(offset: 0)
        let estimate = asUTC.addingTimeInterval(-TimeInterval(timeZone.secondsFromGMT(for: asUTC)))
        return date(offset: timeZone.secondsFromGMT(for: estimate))
    }

    static func < (lhs: WallClock, rhs: WallClock) -> Bool {
        lhs.seconds < rhs.seconds
    }

    // MARK: - Gregorian calendar arithmetic

    struct CivilDate {
        let year: Int
        let month: Int
        let day: Int
    }

    static let secondsPerDay = 86_400

    static func isLeapYear(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }

    static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2:
            return isLeapYear(year) ? 29 : 28
        case 4, 6, 9, 11:
            return 30
        default:
            return 31
        }
    }

    /// Days since 1970-01-01 in the proleptic Gregorian calendar
    ///
    /// Based on Howard Hinnant's `days_from_civil` algorithm.
    static func daysSince1970(year: Int, month: Int, day: Int) -> Int {
        let shiftedYear = month <= 2 ? year - 1 : year
        let era = (shiftedYear >= 0 ? shiftedYear : shiftedYear - 399) / 400
        let yearOfEra = shiftedYear - era * 400
        let monthFromMarch = (month + 9) % 12
        let dayOfYear = (153 * monthFromMarch + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    /// Inverse of `daysSince1970(year:month:day:)`
    static func civilDate(daysSince1970 days: Int) -> CivilDate {
        let shiftedDays = days + 719_468
        let era = (shiftedDays >= 0 ? shiftedDays : shiftedDays - 146_096) / 146_097
        let dayOfEra = shiftedDays - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthFromMarch = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * monthFromMarch + 2) / 5 + 1
        let month = monthFromMarch < 10 ? monthFromMarch + 3 : monthFromMarch - 9
        let year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
        return CivilDate(year: year, month: month, day: day)
    }
}

/// Parses a `UTC-OFFSET` value such as `+0100`, `-0500` or `+053000` into seconds.
///
/// See more in [RFC 5545](
/// https://www.rfc-editor.org/rfc/rfc5545#section-3.3.14)
enum UTCOffset {

    static func seconds(from value: String) -> Int? {
        let characters = Array(value.utf8)
        guard
            characters.count == 5 || characters.count == 7,
            let sign = characters.first,
            sign == UInt8(ascii: "+") || sign == UInt8(ascii: "-"),
            characters.dropFirst().allSatisfy({ (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) })
        else { return nil }

        let values = stride(from: 1, to: characters.count, by: 2).map { index in
            Int(characters[index] - UInt8(ascii: "0")) * 10 + Int(characters[index + 1] - UInt8(ascii: "0"))
        }
        let hours = values[0]
        let minutes = values[1]
        let seconds = values.count > 2 ? values[2] : 0
        guard minutes < 60, seconds < 60 else {
            return nil
        }

        let total = hours * 3_600 + minutes * 60 + seconds
        return sign == UInt8(ascii: "-") ? -total : total
    }
}
