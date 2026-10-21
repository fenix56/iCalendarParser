import Foundation

public struct ICTimeZone: Sendable {

    // MARK: - Properties

    /// The first `DAYLIGHT` observance. Setting it replaces or removes the first one.
    public var daylight: ICSubTimeZone? {
        get { daylightObservances.first }
        set { Self.replaceFirst(of: &daylightObservances, with: newValue) }
    }

    /// Every `DAYLIGHT` observance, in the order of the calendar.
    ///
    /// A definition may have several, such as one for the rules until 2006 and one for those since 2007.
    public var daylightObservances: [ICSubTimeZone]

    /// Any property name with a "X-" prefix
    ///
    /// See more in [RFC 5545](
    /// https://www.rfc-editor.org/rfc/rfc5545#section-3.8.8.2)
    public var nonStandardProperties: [String: String]?

    /// The first `STANDARD` observance. Setting it replaces or removes the first one.
    public var standard: ICSubTimeZone? {
        get { standardObservances.first }
        set { Self.replaceFirst(of: &standardObservances, with: newValue) }
    }

    /// Every `STANDARD` observance, in the order of the calendar.
    ///
    /// A definition may have several, such as one for the rules until 2006 and one for those since 2007.
    public var standardObservances: [ICSubTimeZone]

    /// Specifies the text value that uniquely identifies the "VTIMEZONE" calendar
    /// component in the scope of an iCalendar object.
    ///
    /// See more in [RFC 5545](
    /// https://www.rfc-editor.org/rfc/rfc5545#section-3.8.3.1)
    public var timeZoneId: String

    /// Provides a means for a "VTIMEZONE" component to point to a network
    /// location that can be used to retrieve an up-to-date version of itself.
    ///
    /// See more in [RFC 5545](
    /// https://www.rfc-editor.org/rfc/rfc5545#section-3.8.3.5)
    public var timeZoneUrl: URL?

    public init(
        daylight: ICSubTimeZone? = nil,
        nonStandardProperties: [String: String]? = nil,
        standard: ICSubTimeZone? = nil,
        timeZoneId: String,
        timeZoneUrl: URL? = nil
    ) {
        self.daylightObservances = daylight.map { [$0] } ?? []
        self.nonStandardProperties = nonStandardProperties
        self.standardObservances = standard.map { [$0] } ?? []
        self.timeZoneId = timeZoneId
        self.timeZoneUrl = timeZoneUrl
    }

    private static func replaceFirst(of observances: inout [ICSubTimeZone], with observance: ICSubTimeZone?) {
        if !observances.isEmpty {
            observances.removeFirst()
        }
        if let observance {
            observances.insert(observance, at: 0)
        }
    }
}

/// Two time zones are equal when they have the same `TZID`.
extension ICTimeZone: Equatable {
    public static func == (lhs: ICTimeZone, rhs: ICTimeZone) -> Bool {
        lhs.timeZoneId == rhs.timeZoneId
    }
}

extension ICTimeZone: Identifiable {
    public var id: String {
        timeZoneId
    }
}
