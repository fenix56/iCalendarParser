import Foundation

typealias ICProperty = (name: String, value: String)

public struct ICParser {

    /// How `DATE-TIME` values are bound to a time zone
    public enum TimeZoneHandling: Sendable {

        /// Follows RFC 5545.
        ///
        /// A value without `Z` or `TZID` is floating local time in the device's time zone.
        /// A `TZID` is resolved as a system time zone identifier, including identifiers with a
        /// vendor prefix, and then against the `VTIMEZONE` components of the calendar.
        case standard

        /// Reproduces how dates were parsed before `VTIMEZONE` support.
        ///
        /// - A value without `Z` or `TZID` is read as UTC.
        /// - A `TZID` that is not a system time zone identifier is read in the device's time zone.
        /// - `VTIMEZONE` components are not parsed, so `ICalendar.timeZones` is empty.
        case legacy
    }

    public let timeZoneHandling: TimeZoneHandling

    public init(timeZoneHandling: TimeZoneHandling = .standard) {
        self.timeZoneHandling = timeZoneHandling
    }

    /// Parse strings to create ICalendar object. Returns nil if not found.
    public func calendar(
        from raw: String
    ) -> ICalendar? {

        let elements: [ICProperty] = getProperties(from: raw)

        guard
            let rawValue = getProperty(
                name: Constant.Property.prodid,
                from: elements
            )?.value
        else { return nil }

        let prodId = ICProductIdentifier(rawValue)

        // An iCalendar object MUST include the "PRODID"
        // https://www.rfc-editor.org/rfc/rfc5545#section-3.6)
        guard !prodId.parameters.isEmpty else {
            return nil
        }

        let method = getProperty(
            name: Constant.Property.method,
            from: elements
        )?.value

        let calendarScale = getProperty(
            name: Constant.Property.calScale,
            from: elements
        )?.value

        let timeZoneComponents = getComponents(
            type: .timeZone,
            from: elements
        )

        let eventComponents = getComponents(
            type: .event,
            from: elements
        )

        let timeZones = timeZoneHandling == .legacy ? [] : buildTimeZones(from: timeZoneComponents)
        let events = buildEvents(from: eventComponents, timeZones: timeZones)

        return ICalendar(
            calendarScale: calendarScale,
            events: events,
            method: method,
            productId: prodId,
            timeZones: timeZones
        )
    }

    func getProperties(
        from ics: String
    ) -> [ICProperty] {
        return unfoldedLines(of: ics).compactMap { line -> ICProperty? in
            let parts = line.splitOutsideQuotes(separator: ":", maxSplits: 1)
            guard parts.count > 1, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
            return (name: String(parts[0]), value: String(parts[1]))
        }
    }

    /// Splits the raw text into content lines and unfolds folded lines.
    ///
    /// Accepts CRLF, LF and CR line endings. A line starting with a space or
    /// a horizontal tab continues the previous line.
    ///
    /// See more in [RFC 5545](
    /// https://www.rfc-editor.org/rfc/rfc5545#section-3.1)
    private func unfoldedLines(
        of ics: String
    ) -> [String] {
        let rawLines = ics.split(omittingEmptySubsequences: false) { character in
            character == "\r\n" || character == "\n" || character == "\r"
        }

        var lines = [String]()
        for rawLine in rawLines {
            if let first = rawLine.first, first == " " || first == "\t", !lines.isEmpty {
                lines[lines.count - 1].append(contentsOf: rawLine.dropFirst())
            } else {
                lines.append(String(rawLine))
            }
        }

        if let first = lines.first, first.hasPrefix("\u{FEFF}") {
            lines[0] = String(first.dropFirst())
        }

        return lines
    }

    private func getProperty(
        name: String,
        from elements: [ICProperty]
    ) -> ICProperty? {
        return elements
            .filter { $0.name.hasPrefix(name) }
            .first
    }

    private func getComponents(
        type: ICComponentType,
        from elements: [ICProperty]
    ) -> [ICComponent] {
        getComponents(name: type.name, from: elements)
    }

    private func getComponents(
        name: String,
        from elements: [ICProperty]
    ) -> [ICComponent] {

        var found = [ICComponent]()
        var properties: [ICProperty]?
        var childProperties = [ICProperty]()
        // Nesting depth of child components (e.g. VALARM) inside the current component
        var depth = 0

        for element in elements {
            guard properties != nil else {
                if element.name == Constant.Property.begin, element.value == name {
                    properties = [element]
                    childProperties = []
                    depth = 0
                }
                continue
            }

            if element.name == Constant.Property.begin {
                depth += 1
                childProperties.append(element)
            } else if element.name == Constant.Property.end, depth > 0 {
                depth -= 1
                childProperties.append(element)
            } else if depth > 0 {
                childProperties.append(element)
            } else {
                properties?.append(element)
            }

            if depth == 0,
               element.name == Constant.Property.end,
               element.value == name,
               let componentProperties = properties {
                found.append(ICComponent(properties: componentProperties, childProperties: childProperties))
                properties = nil
            }
        }

        return found
    }

    // MARK: - Build functions

    private func buildEvents(
        from components: [ICComponent],
        timeZones: [ICTimeZone]
    ) -> [ICEvent] {

        return components.map { component -> ICEvent in
            var event = ICEvent()

            func dateTime(_ name: String) -> ICDateTime? {
                component.buildDateTime(of: name, timeZones: timeZones, timeZoneHandling: timeZoneHandling)
            }

            func dateTimes(_ name: String) -> [ICDateTime] {
                PropertyBuilder.buildDateTimes(
                    from: component.getProperties(name: name) ?? [],
                    timeZones: timeZones,
                    timeZoneHandling: timeZoneHandling
                )
            }

            event.attendees = component.buildAttendees(of: Constant.Property.attendee)
            event.classification = component.buildProperty(of: Constant.Property.classification)
            event.description = component.buildText(of: Constant.Property.description)
            event.dtCreated = dateTime(Constant.Property.created)?.date
            event.dtEnd = dateTime(Constant.Property.dtEnd)
            event.dtStamp = dateTime(Constant.Property.dtStamp)?.date ?? Date()
            event.dtStart = dateTime(Constant.Property.dtStart)
            event.duration = component.buildProperty(of: Constant.Property.duration).flatMap(ICDuration.init)
            event.exceptionDates = dateTimes(Constant.Property.exceptionDates)
            event.lastModified = dateTime(Constant.Property.lastModified)?.date
            event.location = component.buildText(of: Constant.Property.location)
            event.organizer = component.buildProperty(of: Constant.Property.organizer)
            event.priority = component.buildProperty(of: Constant.Property.priority)
            event.recurrenceDates = dateTimes(Constant.Property.recurrenceDates)
            event.recurrenceId = dateTime(Constant.Property.recurrenceId)
            event.sequence = component.buildProperty(of: Constant.Property.sequence)
            event.status = component.buildProperty(of: Constant.Property.status)
            event.summary = component.buildText(of: Constant.Property.summary)
            event.timeTransparency = component.buildProperty(of: Constant.Property.timeTransparency)
            event.url = URL(string: component.buildProperty(of: Constant.Property.url) ?? "")
            event.uid = component.buildProperty(of: Constant.Property.uid) ?? ""
            event.recurrenceRule = component.buildRecurrenceRule(
                of: Constant.Property.recurrenceRule,
                timeZoneHandling: timeZoneHandling
            )

            event.nonStandardProperties = component.getNonStandardProperties()

            return event
        }
    }

    private func buildTimeZones(
        from components: [ICComponent]
    ) -> [ICTimeZone] {
        return components.compactMap { component -> ICTimeZone? in
            guard
                let tzid = component.getProperty(
                    name: Constant.Property.tzId
                )?.value
            else { return nil }

            var standard: ICSubTimeZone?
            var daylight: ICSubTimeZone?

            let standardComponent = getComponents(
                name: Constant.Component.standard,
                from: component.childProperties
            ).first

            if let standardComponent,
               let standardSubTimeZone = buildSubTimeZone(from: standardComponent) {
                standard = standardSubTimeZone
            }

            let daylightComponent = getComponents(
                name: Constant.Component.daylight,
                from: component.childProperties
            ).first

            if let daylightComponent,
               let daylightSubTimeZone = buildSubTimeZone(from: daylightComponent) {
                daylight = daylightSubTimeZone
            }

            let nonStandardProperties = component.getNonStandardProperties()

            return ICTimeZone(
                daylight: daylight,
                nonStandardProperties: nonStandardProperties,
                standard: standard,
                timeZoneId: tzid
            )
        }
    }

    private func buildSubTimeZone(
        from component: ICComponent
    ) -> ICSubTimeZone? {
        guard
            let dtStartValue = component.getProperty(
                name: Constant.Property.dtStart
            )?.value,
            let timeZoneOffsetTo = component.getProperty(
                name: Constant.Property.tzOffsetTo
            )?.value,
            let timeZoneOffsetFrom = component.getProperty(
                name: Constant.Property.tzOffsetFrom
            )?.value
        else { return nil }

        // DTSTART of an observance is local time in the offset in use before it
        guard
            let offsetFrom = UTCOffset.seconds(from: timeZoneOffsetFrom),
            let wallClock = WallClock(dtStartValue)
        else { return nil }

        let dtStart = wallClock.date(offset: offsetFrom)

        let timeZoneName: String? = component.buildProperty(of: Constant.Property.tzName)
        let rRule: ICRRule? = component.buildProperty(of: Constant.Property.recurrenceRule)

        return ICSubTimeZone(
            dtStart: dtStart,
            recurrenceRule: rRule,
            timeZoneName: timeZoneName,
            timeZoneOffsetFrom: timeZoneOffsetFrom,
            timeZoneOffsetTo: timeZoneOffsetTo
        )
    }
}
