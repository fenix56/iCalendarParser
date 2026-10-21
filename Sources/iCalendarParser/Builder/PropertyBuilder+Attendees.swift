import Foundation

// MARK: - Attendees and organizer

extension PropertyBuilder {

    static func buildAttendees(
        from props: [ICProperty]
    ) -> [ICAttendee] {
        return props.map { prop -> ICAttendee in
            var attendee = ICAttendee()

            let params = getParamsOfValue(from: prop.name)
            params.forEach { property in
                switch property.name {
                case Constant.Property.cname:
                    attendee.cname = property.value
                case Constant.Property.partstat:
                    attendee.participationStatus = ParticipationStatus(rawValue: property.value)
                case Constant.Property.cuType, Constant.Property.role, Constant.Property.rsvp:
                    setStandardParameter(property, of: &attendee)
                default:
                    if attendee.nonStandardProperties == nil {
                        attendee.nonStandardProperties = [:]
                    }
                    attendee.nonStandardProperties?[property.name] = property.value
                }
            }

            attendee.email = emailAddress(from: prop.value)
            return attendee
        }
    }

    /// Sets `CUTYPE`, `ROLE` or `RSVP` of an attendee.
    ///
    /// They are also kept in `nonStandardProperties`, where earlier versions put them.
    private static func setStandardParameter(_ parameter: ICProperty, of attendee: inout ICAttendee) {
        switch parameter.name {
        case Constant.Property.cuType:
            attendee.calendarUserType = parameter.value.normalizedName
        case Constant.Property.role:
            attendee.role = parameter.value.normalizedName
        default:
            switch parameter.value.normalizedName {
            case "TRUE": attendee.rsvp = true
            case "FALSE": attendee.rsvp = false
            default: attendee.rsvp = nil
            }
        }
        attendee.nonStandardProperties = (attendee.nonStandardProperties ?? [:])
            .merging([parameter.name: parameter.value]) { _, new in new }
    }

    /// Returns the calendar user address without the `mailto:` scheme (case-insensitive)
    static func emailAddress(
        from value: String
    ) -> String {
        let scheme = "mailto:"
        guard value.lowercased().hasPrefix(scheme) else {
            return value
        }
        return String(value.dropFirst(scheme.count))
    }
}
