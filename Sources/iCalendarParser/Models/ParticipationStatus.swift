/// See more in [RFC 5545](
/// https://www.rfc-editor.org/rfc/rfc5545#section-3.2.12)
public enum ParticipationStatus: Sendable {
    case needsAction
    case accepted
    case declined
    case tentative
    case delegated

    @available(*, deprecated, renamed: "tentative")
    public static var tenative: ParticipationStatus {
        .tentative
    }

    /// Creates a status from a `PARTSTAT` value; the value is case-insensitive
    public init?(rawValue: String) {
        switch rawValue.normalizedName {
        case Constant.PartStat.needsAction:
            self = .needsAction
        case Constant.PartStat.accepted:
            self = .accepted
        case Constant.PartStat.declined:
            self = .declined
        case Constant.PartStat.tentative:
            self = .tentative
        case Constant.PartStat.delegated:
            self = .delegated
        default:
            return nil
        }
    }
}
