import Foundation

struct PropertyBuilder {

    // MARK: - Build functions

    /// Returns `ICDateTime` for a `DATE` or `DATE-TIME` property.
    ///
    /// A `TZID` is resolved as a system time zone first, then against the
    /// `VTIMEZONE` definitions in `timeZones`. A local time that cannot be
    /// bound to a time zone is returned as floating.
    ///
    /// See `ICParser.TimeZoneHandling` for how `.legacy` differs.
    static func buildDateTime(
        from prop: ICProperty,
        timeZones: [ICTimeZone] = [],
        timeZoneHandling: ICParser.TimeZoneHandling = .standard
    ) -> ICDateTime? {
        let params = getParamsOfValue(from: prop.name)
        let isUTC = prop.value.utf8.last == UInt8(ascii: "Z")
        let value = isUTC ? String(prop.value.dropLast()) : prop.value

        guard let wallClock = WallClock(value) else {
            return nil
        }

        let type = getDateTimeType(from: params, value: value)
        // A TZID is ignored for DATE values and for UTC times
        let tzid = type == .dateTime && !isUTC ? getTimeZoneId(from: params) : nil
        let zone = resolveZone(
            type: type,
            isUTC: isUTC,
            tzid: tzid,
            timeZones: timeZones,
            timeZoneHandling: timeZoneHandling
        )

        var dateTime = ICDateTime(
            date: (zone ?? .system(.current)).date(for: wallClock),
            type: type,
            tzId: tzid,
            isFloating: type == .dateTime && !isUTC && (tzid == nil || zone == nil)
        )
        dateTime.zone = zone ?? .system(.current)
        return dateTime
    }

    /// Returns `ICDateTime` values of a list property such as `EXDATE` or `RDATE`.
    ///
    /// Each property may hold a comma-separated list. For a `PERIOD` value only the start is used.
    static func buildDateTimes(
        from props: [ICProperty],
        timeZones: [ICTimeZone] = [],
        timeZoneHandling: ICParser.TimeZoneHandling = .standard
    ) -> [ICDateTime] {
        props.flatMap { prop in
            prop.value
                .split(separator: ",")
                .compactMap { item -> ICDateTime? in
                    let start = item.split(separator: "/", maxSplits: 1).first.map(String.init) ?? ""
                    return buildDateTime(
                        from: (name: prop.name, value: start),
                        timeZones: timeZones,
                        timeZoneHandling: timeZoneHandling
                    )
                }
        }
    }

    /// Returns the zone for a value, or nil when a floating local time falls back to the device's time zone
    private static func resolveZone(
        type: DateTimeType,
        isUTC: Bool,
        tzid: String?,
        timeZones: [ICTimeZone],
        timeZoneHandling: ICParser.TimeZoneHandling
    ) -> DateTimeZone? {
        if type == .date {
            return .system(.current)
        }

        if isUTC {
            return .utc
        }

        guard let tzid else {
            return timeZoneHandling == .legacy ? .utc : nil
        }

        let timeZone = timeZoneHandling == .legacy
            ? TimeZone(identifier: tzid)
            : TimeZoneResolver.timeZone(for: tzid)

        if let timeZone {
            return .system(timeZone)
        }

        if timeZoneHandling == .standard,
           let definition = timeZones.first(where: { $0.timeZoneId == tzid }),
           definition.date(for: WallClock(seconds: 0)) != nil {
            return .definition(definition)
        }

        return nil
    }

    // swiftlint:disable:next cyclomatic_complexity
    static func buildRRule(
        from prop: ICProperty,
        timeZoneHandling: ICParser.TimeZoneHandling = .standard
    ) -> ICRRule? {
        let params = getParamsOfValue(from: prop.value)
        let frequencyProperty = params
            .filter { $0.name == Constant.Property.frequency }
            .first

        guard
            let frequencyProperty = frequencyProperty,
            let frequency = ICRRule.Frequency(propertyName: frequencyProperty.value)
        else { return nil }

        var rule = ICRRule(frequency: frequency)

        params.forEach { property in
            switch property.name {
            case Constant.Property.interval:
                rule.interval = Int(property.value)
            case Constant.Property.until:
                rule.until = buildDateTime(from: property, timeZoneHandling: timeZoneHandling)
            case Constant.Property.count:
                rule.count = Int(property.value)
            case Constant.Property.bySecond:
                rule.bySecond = getIntComponents(from: property.value)
            case Constant.Property.byMinute:
                rule.byMinute = getIntComponents(from: property.value)
            case Constant.Property.byHour:
                rule.byHour = getIntComponents(from: property.value)
            case Constant.Property.byDay:
                rule.byDay = getDayComponents(from: property.value)
            case Constant.Property.byDayOfMonth:
                rule.byDayOfMonth = getIntComponents(from: property.value)
            case Constant.Property.byDayOfYear:
                rule.byDayOfYear = getIntComponents(from: property.value)
            case Constant.Property.byWeekOfYear:
                rule.byWeekOfYear = getIntComponents(from: property.value)
            case Constant.Property.byMonth:
                rule.byMonth = getIntComponents(from: property.value)
            case Constant.Property.bySetPos:
                rule.bySetPos = getIntComponents(from: property.value)
            case Constant.Property.startOfWorkweek:
                rule.startOfWorkweek = .init(propertyName: property.value)
            default:
                break
            }
        }

        return rule
    }

    static func buildAttendees(
        from props: [ICProperty]
    ) -> [ICAttendee]? {
        return props.map { prop -> ICAttendee in
            var attendee = ICAttendee()

            let params = getParamsOfValue(from: prop.name)
            params.forEach { property in
                switch property.name {
                case Constant.Property.cname:
                    attendee.cname = property.value
                case Constant.Property.partstat:
                    attendee.participationStatus = ParticipationStatus(rawValue: property.value)
                default:
                    if attendee.nonStandardProperties == nil {
                        attendee.nonStandardProperties = [:]
                    }
                    attendee.nonStandardProperties?[property.name] = property.value
                }
            }

            attendee.email = removingMailtoScheme(from: prop.value)
            return attendee
        }
    }

    /// Returns the value of a parameter of a property, e.g. `RANGE` of `RECURRENCE-ID;RANGE=THISANDFUTURE`
    static func parameter(
        _ name: String,
        of prop: ICProperty
    ) -> String? {
        getParamsOfValue(from: prop.name).first { $0.name.uppercased() == name }?.value
    }

    /// Returns the value of a `TEXT` property with escaped characters restored.
    ///
    /// `\n` and `\N` become a line break; `\\`, `\;` and `\,` become the
    /// escaped character. Any other backslash sequence is kept as is.
    ///
    /// See more in [RFC 5545](
    /// https://www.rfc-editor.org/rfc/rfc5545#section-3.3.11)
    static func unescapeText(
        _ value: String
    ) -> String {
        guard value.utf8.contains(UInt8(ascii: "\\")) else {
            return value
        }

        // Escapes are ASCII, so the UTF-8 bytes can be processed without decoding characters
        let backslash = UInt8(ascii: "\\")
        var result = [UInt8]()
        result.reserveCapacity(value.utf8.count)
        var isEscaped = false

        for byte in value.utf8 {
            if isEscaped {
                switch byte {
                case UInt8(ascii: "n"), UInt8(ascii: "N"):
                    result.append(UInt8(ascii: "\n"))
                case backslash, UInt8(ascii: ";"), UInt8(ascii: ","):
                    result.append(byte)
                default:
                    result.append(backslash)
                    result.append(byte)
                }
                isEscaped = false
            } else if byte == backslash {
                isEscaped = true
            } else {
                result.append(byte)
            }
        }

        if isEscaped {
            result.append(backslash)
        }

        // Only ASCII escapes were changed in valid UTF-8, so decoding cannot fail
        return String(decoding: result, as: UTF8.self) // swiftlint:disable:this optional_data_string_conversion
    }

    // MARK: - Private functions

    /// Returns an array of params for the given value
    ///
    /// Separators inside quoted parameter values are ignored and the
    /// surrounding quotes are removed from the returned values.
    private static func getParamsOfValue(
        from value: String
    ) -> [ICProperty] {
        return value
            .splitOutsideQuotes(separator: ";")
            .compactMap { param -> ICProperty? in
                guard let equals = param.utf8.firstIndex(of: UInt8(ascii: "=")) else {
                    return nil
                }
                let paramValue = param[param.utf8.index(after: equals)...]
                let unquoted = paramValue.utf8.contains(UInt8(ascii: "\""))
                    ? String(paramValue.filter { $0 != "\"" })
                    : String(paramValue)
                return (name: String(param[..<equals]), value: unquoted)
            }
    }

    /// Returns the calendar user address without the `mailto:` scheme (case-insensitive)
    private static func removingMailtoScheme(
        from value: String
    ) -> String {
        let scheme = "mailto:"
        guard value.lowercased().hasPrefix(scheme) else {
            return value
        }
        return String(value.dropFirst(scheme.count))
    }

    /// Returns `ICDateTimeType` from the given properties
    ///
    /// Without a `VALUE` parameter the type is inferred from the value, so
    /// that e.g. `UNTIL=20240110` in a recurrence rule is read as a `DATE`.
    private static func getDateTimeType(
        from params: [ICProperty],
        value: String
    ) -> DateTimeType {
        guard
            let valueType = params.first(where: {
                $0.name == Constant.Property.value
            })?.value
        else {
            return value.contains("T") ? .dateTime : .date
        }

        switch valueType {
        case Constant.Property.date:
            return .date
        default:
            return .dateTime
        }
    }

    /// Returns the ID for Timezone component
    private static func getTimeZoneId(
        from parameters: [ICProperty]
    ) -> String? {
        return parameters.first(where: {
            $0.name == Constant.Property.tzId
        })?.value
    }

    private static func getIntComponents(
        from value: String
    ) -> [Int] {
        value
            .components(separatedBy: ",")
            .compactMap { Int($0) }
    }

    private static func getDayComponents(
        from value: String
    ) -> [ICRRule.Day] {
        value
            .components(separatedBy: ",")
            .compactMap { .from($0) }
    }
}
