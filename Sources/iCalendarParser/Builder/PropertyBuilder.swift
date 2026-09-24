import Foundation

struct PropertyBuilder {

    // MARK: - Build functions

    static func buildDateTime(
        from prop: ICProperty
    ) -> ICDateTime? {
        let params = getParamsOfValue(from: prop.name)
        let valueType = getDateTimeType(from: params)
        let tzid = getTimeZoneId(from: params)

        guard
            let date = valueType.dateFormatter(tzId: tzid).date(from: prop.value)
        else {
            return nil
        }

        switch valueType {
        case .date:
            return .date(from: date)
        default:
            return .dateTime(from: date, tzId: tzid)
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    static func buildRRule(
        from prop: ICProperty
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
                rule.until = buildDateTime(from: property)
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
        var result = ""
        result.reserveCapacity(value.count)
        var isEscaped = false

        for character in value {
            if isEscaped {
                switch character {
                case "n", "N":
                    result.append("\n")
                case "\\", ";", ",":
                    result.append(character)
                default:
                    result.append("\\")
                    result.append(character)
                }
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else {
                result.append(character)
            }
        }

        if isEscaped {
            result.append("\\")
        }

        return result
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
                let parts = param.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count > 1 else { return nil }
                let paramValue = parts[1].replacingOccurrences(of: "\"", with: "")
                return (name: String(parts[0]), value: paramValue)
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
    /// The default value is `.dateTime` if no property is found
    private static func getDateTimeType(
        from params: [ICProperty]
    ) -> DateTimeType {
        guard
            let valueType = params.first(where: {
                $0.name == Constant.Property.value
            })?.value
        else {
            return .dateTime
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
