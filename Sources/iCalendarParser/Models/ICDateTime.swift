import Foundation

public struct ICDateTime: Sendable {

    public var date: Date
    public var type: DateTimeType
    public var tzId: String?

    /// `true` for a local time that is not bound to a time zone: a `DATE-TIME` without
    /// the `Z` suffix and without a `TZID`, or with a `TZID` that could not be resolved.
    ///
    /// `date` is then interpreted in the device's current time zone, except for a value
    /// without a `TZID` parsed with `ICParser.TimeZoneHandling.legacy`, which is read as UTC.
    ///
    /// See more in [RFC 5545](
    /// https://www.rfc-editor.org/rfc/rfc5545#section-3.3.5)
    public var isFloating: Bool

    /// The zone the value was resolved in when parsed; nil for a value created in code
    var zone: DateTimeZone?

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
