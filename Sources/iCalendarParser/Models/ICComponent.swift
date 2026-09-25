import Foundation

struct ICComponent {
    let properties: [ICProperty]
    let childProperties: [ICProperty]

    /// Returns a property that matches the name
    func getProperty(
        name: String
    ) -> ICProperty? {
        properties.first { Self.hasName($0, name) }
    }

    /// Returns a property that matches the name
    func getProperties(
        name: String
    ) -> [ICProperty]? {
        properties.filter { Self.hasName($0, name) }
    }

    /// Whether the property name, including any parameters, starts with `name`.
    ///
    /// Compares UTF-8 bytes: property names are ASCII, and this is much faster than `hasPrefix`.
    private static func hasName(_ property: ICProperty, _ name: String) -> Bool {
        property.name.utf8.starts(with: name.utf8)
    }

    // MARK: - Build property

    /// Returns `ICDateTime` from properties
    func buildProperty(
        of name: String
    ) -> ICDateTime? {
        buildDateTime(of: name, timeZones: [])
    }

    /// Returns `ICDateTime` from properties, resolving `TZID` against the given time zone definitions
    func buildDateTime(
        of name: String,
        timeZones: [ICTimeZone],
        timeZoneHandling: ICParser.TimeZoneHandling = .standard
    ) -> ICDateTime? {
        guard let prop = getProperty(name: name) else {
            return nil
        }

        return PropertyBuilder.buildDateTime(from: prop, timeZones: timeZones, timeZoneHandling: timeZoneHandling)
    }

    /// Returns `String` from properties
    func buildProperty(
        of name: String
    ) -> String? {
        guard let prop = getProperty(name: name) else {
            return nil
        }

        return prop.value
    }

    /// Returns an unescaped `TEXT` value from properties
    func buildText(
        of name: String
    ) -> String? {
        guard let prop = getProperty(name: name) else {
            return nil
        }

        return PropertyBuilder.unescapeText(prop.value)
    }

    /// Returns `Int` from properties
    func buildProperty(
        of name: String
    ) -> Int? {
        guard let prop = getProperty(name: name) else {
            return nil
        }

        return Int(prop.value)
    }

    /// Returns `ICRRule` from properties
    func buildProperty(
        of name: String
    ) -> ICRRule? {
        buildRecurrenceRule(of: name, timeZoneHandling: .standard)
    }

    /// Returns `ICRRule` from properties, parsing `UNTIL` with the given time zone handling
    func buildRecurrenceRule(
        of name: String,
        timeZoneHandling: ICParser.TimeZoneHandling
    ) -> ICRRule? {
        guard let prop = getProperty(name: name) else {
            return nil
        }

        return PropertyBuilder.buildRRule(from: prop, timeZoneHandling: timeZoneHandling)
    }

    /// Returns `[Attendee]` from properties
    func buildAttendees(
        of name: String
    ) -> [ICAttendee]? {
        guard let props = getProperties(name: name) else {
            return nil
        }

        return PropertyBuilder.buildAttendees(from: props)
    }

    /// Returns all non-standard properties if exists
    func getNonStandardProperties() -> [String: String]? {
        var dict = [String: String]()

        properties
            .filter { Self.hasName($0, "X-") }
            .forEach { dict[$0.name] = $0.value }

        guard !dict.isEmpty else {
            return nil
        }

        return dict
    }
}
