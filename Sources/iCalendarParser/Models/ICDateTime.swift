import Foundation

public struct ICDateTime: Sendable {

    public var date: Date {
        didSet {
            if date != oldValue {
                parsedWallClock = nil
            }
        }
    }

    public var type: DateTimeType {
        didSet {
            if type != oldValue {
                clearParsedZone()
            }
        }
    }

    public var tzId: String? {
        didSet {
            if tzId != oldValue {
                clearParsedZone()
            }
        }
    }

    /// `true` for a local time that is not bound to a time zone: a `DATE-TIME` without
    /// the `Z` suffix and without a `TZID`, or with a `TZID` that could not be resolved.
    ///
    /// `date` is then interpreted in the device's current time zone, except for a value
    /// without a `TZID` parsed with `ICParser.TimeZoneHandling.legacy`, which is read as UTC.
    ///
    /// See more in [RFC 5545](
    /// https://www.rfc-editor.org/rfc/rfc5545#section-3.3.5)
    public var isFloating: Bool {
        didSet {
            if isFloating != oldValue {
                clearParsedZone()
            }
        }
    }

    /// The zone the value was resolved in when parsed; nil for a value created in code,
    /// and once a property it depends on changes
    var zone: DateTimeZone?

    /// The wall-clock time as written when parsed; nil for a value created in code,
    /// and once `date` or the zone changes
    var parsedWallClock: WallClock?

    public init(
        date: Date,
        type: DateTimeType,
        tzId: String? = nil,
        isFloating: Bool = false
    ) {
        self.date = date
        self.type = type
        self.tzId = tzId
        self.isFloating = isFloating
    }

    private mutating func clearParsedZone() {
        zone = nil
        parsedWallClock = nil
    }

    public static func date(
        from date: Date
    ) -> Self {
        Self(date: date, type: .date, tzId: nil)
    }

    public static func dateTime(
        from date: Date,
        tzId: String? = nil
    ) -> Self {
        Self(date: date, type: .dateTime, tzId: tzId)
    }
}

extension ICDateTime: Equatable {
    public static func == (lhs: ICDateTime, rhs: ICDateTime) -> Bool {
        lhs.date == rhs.date
        && lhs.type == rhs.type
        && lhs.tzId == rhs.tzId
        && lhs.isFloating == rhs.isFloating
    }
}
