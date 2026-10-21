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

    /// Returns the properties that match the name
    func getProperties(
        name: String
    ) -> [ICProperty] {
        properties.filter { Self.hasName($0, name) }
    }

    /// Whether the property, which may have parameters, is named `name`
    private static func hasName(_ property: ICProperty, _ name: String) -> Bool {
        property.name.hasPropertyName(name)
    }

    // MARK: - Build property

    /// Returns `ICDateTime` from properties, resolving `TZID` with `lookup`
    func buildDateTime(
        of name: String,
        lookup: TimeZoneLookup
    ) -> ICDateTime? {
        guard let prop = getProperty(name: name) else {
            return nil
        }

        return PropertyBuilder.buildDateTime(from: prop, lookup: lookup)
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
    ) -> [ICAttendee] {
        PropertyBuilder.buildAttendees(from: getProperties(name: name))
    }

    /// Returns all non-standard properties if exists
    func getNonStandardProperties() -> [String: String]? {
        var dict = [String: String]()

        properties
            .filter { $0.name.utf8.starts(with: "X-".utf8) }
            .forEach { dict[$0.name.propertyBaseName] = $0.value }

        guard !dict.isEmpty else {
            return nil
        }

        return dict
    }
}
