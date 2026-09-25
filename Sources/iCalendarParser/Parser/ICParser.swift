import Foundation

typealias ICProperty = (name: String, value: String)

public struct ICParser: Sendable {

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
        parseCalendar(from: raw, checkCancellation: {})
    }

    /// Parse strings to create ICalendar object. Returns nil if not found.
    ///
    /// Calls `isCancelled` regularly while parsing and throws `CancellationError`
    /// as soon as it returns `true`. Inside a task, pass `{ Task.isCancelled }`:
    ///
    /// ```swift
    /// let calendar = try parser.calendar(from: raw) { Task.isCancelled }
    /// ```
    public func calendar(
        from raw: String,
        isCancelled: () -> Bool
    ) throws -> ICalendar? {
        try parseCalendar(from: raw) {
            if isCancelled() {
                throw CancellationError()
            }
        }
    }

    private func parseCalendar(
        from raw: String,
        checkCancellation: () throws -> Void
    ) rethrows -> ICalendar? {

        let elements: [ICProperty] = try getProperties(from: raw, checkCancellation: checkCancellation)

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

        let timeZoneComponents = try getComponents(
            name: ICComponentType.timeZone.name,
            from: elements,
            checkCancellation: checkCancellation
        )

        let eventComponents = try getComponents(
            name: ICComponentType.event.name,
            from: elements,
            checkCancellation: checkCancellation
        )

        let timeZones = timeZoneHandling == .legacy
            ? []
            : try buildTimeZones(from: timeZoneComponents, checkCancellation: checkCancellation)
        let events = try buildEvents(from: eventComponents, timeZones: timeZones, checkCancellation: checkCancellation)

        return ICalendar(
            calendarScale: calendarScale,
            events: events,
            method: method,
            productId: prodId,
            timeZones: timeZones
        )
    }

}

// MARK: - Content lines and components

extension ICParser {

    func getProperties(
        from ics: String
    ) -> [ICProperty] {
        getProperties(from: ics, checkCancellation: {})
    }

    func getProperties(
        from ics: String,
        checkCancellation: () throws -> Void
    ) rethrows -> [ICProperty] {
        try ContentLineScanner.properties(in: ics, checkCancellation: checkCancellation)
    }

    private func getProperty(
        name: String,
        from elements: [ICProperty]
    ) -> ICProperty? {
        elements.first { $0.name.utf8.starts(with: name.utf8) }
    }

    private func getComponents(
        name: String,
        from elements: [ICProperty],
        checkCancellation: () throws -> Void
    ) rethrows -> [ICComponent] {

        var found = [ICComponent]()
        var properties: [ICProperty]?
        var childProperties = [ICProperty]()
        // Nesting depth of child components (e.g. VALARM) inside the current component
        var depth = 0

        for element in elements {
            try checkCancellation()

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

}

// MARK: - Build functions

extension ICParser {

    private func buildEvents(
        from components: [ICComponent],
        timeZones: [ICTimeZone],
        checkCancellation: () throws -> Void
    ) rethrows -> [ICEvent] {

        return try components.map { component -> ICEvent in
            try checkCancellation()

            // UID and DTSTAMP are set below; avoid generating default values for them
            var event = ICEvent(dtStamp: .distantPast, uid: "")

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
            event.appliesToFutureOccurrences = component
                .getProperty(name: Constant.Property.recurrenceId)
                .flatMap { PropertyBuilder.parameter(Constant.Property.range, of: $0) }?
                .uppercased() == Constant.Property.thisAndFuture
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
        from components: [ICComponent],
        checkCancellation: () throws -> Void
    ) rethrows -> [ICTimeZone] {
        return try components.compactMap { component -> ICTimeZone? in
            try checkCancellation()

            guard
                let tzid = component.getProperty(
                    name: Constant.Property.tzId
                )?.value
            else { return nil }

            var standard: ICSubTimeZone?
            var daylight: ICSubTimeZone?

            let standardComponent = getComponents(
                name: Constant.Component.standard,
                from: component.childProperties,
                checkCancellation: {}
            ).first

            if let standardComponent,
               let standardSubTimeZone = buildSubTimeZone(from: standardComponent) {
                standard = standardSubTimeZone
            }

            let daylightComponent = getComponents(
                name: Constant.Component.daylight,
                from: component.childProperties,
                checkCancellation: {}
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
