/// Identify properties that contain a recurrence rule specification.
///
/// A `BYxxx` list with a value outside its valid range is set to nil, both when it is assigned
/// and in the initializer.
///
/// See more in [RFC 5545](
/// https://www.rfc-editor.org/rfc/rfc5545#section-3.3.10)
public struct ICRRule: Equatable, Sendable {

    // MARK: - Public properties

    /// At which days (of the week/year) it should occur.
    public var byDay: [Day]?

    /// At which days of the month it should occur. Specifies a COMMA-separated
    /// list of days of the month.
    ///
    /// Valid values are 1 to 31 or -31 to -1.
    public var byDayOfMonth: [Int]? {
        didSet {
            byDayOfMonth = Self.valid(byDayOfMonth, 1...31, allowsNegative: true)
        }
    }

    /// At which days of the year it should occur. Specifies a list of days
    /// of the year.
    ///
    /// Valid values are 1 to 366 or -366 to -1.
    public var byDayOfYear: [Int]? {
        didSet {
            byDayOfYear = Self.valid(byDayOfYear, 1...366, allowsNegative: true)
        }
    }

    /// At which hours of the day it should occur.
    ///
    /// Must be between 0 and 24 (exclusive).
    public var byHour: [Int]? {
        didSet {
            byHour = Self.valid(byHour, 0...23)
        }
    }

    /// At which minutes of the hour it should occur.
    ///
    /// Must be between 0 and 60 (exclusive).
    public var byMinute: [Int]? {
        didSet {
            byMinute = Self.valid(byMinute, 0...59)
        }
    }

    /// At which months it should occur.
    ///
    /// Must be between 1 and 12 (inclusive).
    public var byMonth: [Int]? {
        didSet {
            byMonth = Self.valid(byMonth, 1...12)
        }
    }

    /// At which seconds of the minute it should occur.
    /// Must be between 0 and 60 (inclusive).
    public var bySecond: [Int]? {
        didSet {
            bySecond = Self.valid(bySecond, 0...60)
        }
    }

    /// Specifies a COMMA-separated list of values that corresponds to the nth occurrence within
    /// the set of recurrence instances specified by the rule. BYSETPOS operates on a set of
    /// recurrence instances in one interval of the recurrence rule.  For example, in a WEEKLY rule,
    /// the interval would be one week A set of recurrence instances starts at the beginning of
    /// theinterval defined by the FREQ rule part.
    ///
    /// Valid values are 1 to 366 or -366 to -1.
    /// It MUST only be used in conjunction with another BYxxx rule part.
    public var bySetPos: [Int]? {
        didSet {
            bySetPos = Self.valid(bySetPos, 1...366, allowsNegative: true)
        }
    }

    /// At which weeks of the year it should occur. Specificies a list of
    /// ordinals specifying weeks of the year.
    ///
    /// Valid values are 1 to 53 or -53 to -1.
    public var byWeekOfYear: [Int]? {
        didSet {
            byWeekOfYear = Self.valid(byWeekOfYear, 1...53, allowsNegative: true)
        }
    }

    /// The number of recurrences.
    public var count: Int? {
        willSet {
            if newValue != nil {
                until = nil
            }
        }
    }

    /// The frequency of the recurrence.
    public var frequency: Frequency

    /// At which interval the recurrence repeats (in terms of the frequency).
    /// E.g. 1 means every hour for an hourly rule, ...
    ///
    /// The default value is 1.
    public var interval: Int?

    /// The day on which the workweek starts.
    ///
    /// Monday by default.
    public var startOfWorkweek: DayOfWeek?

    /// The end date/time.
    public var until: ICDateTime? {
        willSet {
            if newValue != nil {
                count = nil
            }
        }
    }

    // MARK: - Init

    public init(
        byDay: [Day]? = nil,
        byDayOfMonth: [Int]? = nil,
        byDayOfYear: [Int]? = nil,
        byHour: [Int]? = nil,
        byMinute: [Int]? = nil,
        byMonth: [Int]? = nil,
        bySecond: [Int]? = nil,
        bySetPos: [Int]? = nil,
        byWeekOfYear: [Int]? = nil,
        count: Int? = nil,
        frequency: Frequency,
        interval: Int? = nil,
        startOfWorkweek: DayOfWeek? = nil,
        until: ICDateTime? = nil
    ) {
        // Property observers do not run in an initializer, so validate here as well
        self.byDay = byDay
        self.byDayOfMonth = Self.valid(byDayOfMonth, 1...31, allowsNegative: true)
        self.byDayOfYear = Self.valid(byDayOfYear, 1...366, allowsNegative: true)
        self.byHour = Self.valid(byHour, 0...23)
        self.byMinute = Self.valid(byMinute, 0...59)
        self.byMonth = Self.valid(byMonth, 1...12)
        self.bySecond = Self.valid(bySecond, 0...60)
        self.bySetPos = Self.valid(bySetPos, 1...366, allowsNegative: true)
        self.byWeekOfYear = Self.valid(byWeekOfYear, 1...53, allowsNegative: true)
        // COUNT and UNTIL must not both be set: UNTIL wins, as when they are assigned one after the other
        self.count = until == nil ? count : nil
        self.frequency = frequency
        self.interval = interval
        self.startOfWorkweek = startOfWorkweek
        self.until = until
    }

    /// Returns `values` when every value is in `range`, or in its negative when `allowsNegative`;
    /// otherwise nil, as a rule part with an invalid value is invalid as a whole
    private static func valid(
        _ values: [Int]?,
        _ range: ClosedRange<Int>,
        allowsNegative: Bool = false
    ) -> [Int]? {
        guard let values else {
            return nil
        }
        // Not `abs`, which overflows for `Int.min`
        let negativeRange = -range.upperBound...(-range.lowerBound)
        let isValid = values.allSatisfy { range.contains($0) || (allowsNegative && negativeRange.contains($0)) }
        return isValid ? values : nil
    }
}

// MARK: - Nested types

extension ICRRule {

    // MARK: - Frequency

    public enum Frequency: Sendable {
        case secondly
        case minutely
        case hourly
        case daily
        case weekly
        case monthly
        case yearly

        init?(propertyName: String) {
            switch propertyName {
            case Constant.Frequency.secondly:
                self = .secondly
            case Constant.Frequency.minutely:
                self = .minutely
            case Constant.Frequency.hourly:
                self = .hourly
            case Constant.Frequency.daily:
                self = .daily
            case Constant.Frequency.weekly:
                self = .weekly
            case Constant.Frequency.monthly:
                self = .monthly
            case Constant.Frequency.yearly:
                self = .yearly
            default:
                return nil
            }
        }
    }

    public enum DayOfWeek: Sendable {
        case monday
        case tuesday
        case wednesday
        case thursday
        case friday
        case saturday
        case sunday

        public var weekday: Int {
            switch self {
            case .sunday:
                return 1
            case .monday:
                return 2
            case .tuesday:
                return 3
            case .wednesday:
                return 4
            case .thursday:
                return 5
            case .friday:
                return 6
            case .saturday:
                return 7
            }
        }

        init?(propertyName: String) {
            switch propertyName {
            case Constant.DayOfWeek.monday:
                self = .monday
            case Constant.DayOfWeek.tuesday:
                self = .tuesday
            case Constant.DayOfWeek.wednesday:
                self = .wednesday
            case Constant.DayOfWeek.thursday:
                self = .thursday
            case Constant.DayOfWeek.friday:
                self = .friday
            case Constant.DayOfWeek.saturday:
                self = .saturday
            case Constant.DayOfWeek.sunday:
                self = .sunday
            default:
                return nil
            }
        }
    }

    // MARK: - Day

    public struct Day: Equatable, Sendable {

        /// The week. May be negative.
        public let week: Int?

        /// The day of the week.
        public let dayOfWeek: DayOfWeek

        public init(
            week: Int? = nil,
            dayOfWeek: DayOfWeek
        ) {
            self.dayOfWeek = dayOfWeek

            // An ordinal outside 1...53 or -53...-1 is ignored; not `abs`, which overflows for `Int.min`
            if let week, !(1...53).contains(week), !(-53...(-1)).contains(week) {
                self.week = nil
            } else {
                self.week = week
            }
        }

        public static func every(_ dayOfWeek: DayOfWeek) -> Self {
            Self(dayOfWeek: dayOfWeek)
        }

        public static func first(_ dayOfWeek: DayOfWeek) -> Self {
            Self(week: 1, dayOfWeek: dayOfWeek)
        }

        public static func last(_ dayOfWeek: DayOfWeek) -> Self {
            Self(week: -1, dayOfWeek: dayOfWeek)
        }

        public static func from(_ value: String) -> Self? {
            // A weekday is always two characters, e.g. "MO" or "-1SU"
            guard value.count >= 2 else {
                return nil
            }

            let index = value.index(value.endIndex, offsetBy: -2)

            let dayOfWeekStr = String(value[index...])
            let weekStr = String(value[..<index])

            guard let dayOfWeek = DayOfWeek(propertyName: dayOfWeekStr) else {
                return nil
            }

            return Self(week: Int(weekStr), dayOfWeek: dayOfWeek)
        }
    }
}
