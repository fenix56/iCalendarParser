import Foundation

/// The zone a parsed date was resolved in, used to convert between instants and wall-clock times
enum DateTimeZone: Equatable, Sendable {

    /// A system time zone, including UTC and the device's time zone
    case system(TimeZone)

    /// A `VTIMEZONE` definition from the calendar
    ///
    /// Indirect because a definition contains dates (`UNTIL`) that refer back to their zone.
    indirect case definition(ICTimeZone)

    static var utc: DateTimeZone {
        .system(TimeZone(secondsFromGMT: 0) ?? .current)
    }

    /// The UTC offset in seconds in effect at `date`
    func offset(at date: Date) -> Int {
        switch self {
        case .system(let timeZone):
            return timeZone.secondsFromGMT(for: date)
        case .definition(let definition):
            return definition.offset(at: date) ?? 0
        }
    }

    func date(for wallClock: WallClock) -> Date {
        switch self {
        case .system(let timeZone):
            return wallClock.date(in: timeZone)
        case .definition(let definition):
            return definition.date(for: wallClock) ?? wallClock.date(offset: 0)
        }
    }

    func wallClock(for date: Date) -> WallClock {
        WallClock(date: date, offset: offset(at: date))
    }
}

extension ICDateTime {

    /// The zone to expand recurrences in: the zone this value was parsed in, or one
    /// derived from its properties for a value created or changed in code
    var resolvedZone: DateTimeZone {
        if let zone {
            return zone
        }

        if type == .date || isFloating {
            return .system(.current)
        }

        if let tzId, let timeZone = TimeZoneResolver.timeZone(for: tzId) {
            return .system(timeZone)
        }

        return .utc
    }

    /// The wall-clock time of this value in `resolvedZone`: as written when parsed, which differs
    /// from the time of `date` for a time skipped when clocks go forward
    var wallClock: WallClock {
        parsedWallClock ?? resolvedZone.wallClock(for: date)
    }
}
