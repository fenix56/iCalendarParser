/// This property defines an "Attendee" within a calendar component.
///
/// See more in [RFC 5545](
/// https://www.rfc-editor.org/rfc/rfc5545#section-3.8.4.1)
public struct ICAttendee: Equatable, Sendable {

    /// The kind of calendar user (`CUTYPE`), such as `INDIVIDUAL`, `GROUP`, `RESOURCE` or `ROOM`
    public var calendarUserType: String?

    /// Common name
    public var cname: String?

    /// The calendar user address without the `mailto:` scheme
    public var email: String?

    /// The parameters other than `CN` and `PARTSTAT`, by name.
    ///
    /// Besides non-standard `X-` parameters this also holds `CUTYPE`, `ROLE` and `RSVP`, which are
    /// available as `calendarUserType`, `role` and `rsvp` too.
    public var nonStandardProperties: [String: String]?

    /// Participation status of attendee
    public var participationStatus: ParticipationStatus?

    /// The role in the event (`ROLE`), such as `CHAIR`, `REQ-PARTICIPANT` or `OPT-PARTICIPANT`
    public var role: String?

    /// Whether a reply is expected (`RSVP`)
    public var rsvp: Bool?

    public init(
        calendarUserType: String? = nil,
        cname: String? = nil,
        email: String? = nil,
        nonStandardProperties: [String: String]? = nil,
        participationStatus: ParticipationStatus? = nil,
        role: String? = nil,
        rsvp: Bool? = nil
    ) {
        self.calendarUserType = calendarUserType
        self.cname = cname
        self.email = email
        self.nonStandardProperties = nonStandardProperties
        self.participationStatus = participationStatus
        self.role = role
        self.rsvp = rsvp
    }
}
