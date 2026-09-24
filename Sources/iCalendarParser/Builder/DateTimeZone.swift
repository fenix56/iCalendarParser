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

    func date(for wallClock: WallClock) -> Date {
        switch self {
        case .system(let timeZone):
            return wallClock.date(in: timeZone)
        case .definition(let definition):
            return definition.date(for: wallClock) ?? wallClock.date(offset: 0)
        }
    }

    func wallClock(for date: Date) -> WallClock {
        switch self {
        case .system(let timeZone):
            return WallClock(date: date, offset: timeZone.secondsFromGMT(for: date))
        case .definition(let definition):
            // The offset in effect is one of the observance offsets: use the one that maps back to `date`
            let offsets = [definition.standard, definition.daylight]
                .compactMap { $0 }
                .flatMap { [$0.timeZoneOffsetTo, $0.timeZoneOffsetFrom] }
                .compactMap { UTCOffset.seconds(from: $0) }
            let match = offsets
                .map { WallClock(date: date, offset: $0) }
                .first { definition.date(for: $0) == date }
            return match ?? WallClock(date: date, offset: 0)
        }
    }
}

extension ICDateTime {

    /// The zone to expand recurrences in: the zone this value was parsed in, or one
    /// derived from its properties for a value created in code
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

    /// The wall-clock time of this value in `resolvedZone`
    var wallClock: WallClock {
        resolvedZone.wallClock(for: date)
    }
}
