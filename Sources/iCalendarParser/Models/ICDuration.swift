import Foundation

/// A duration of time, such as `PT1H30M` or `P1D`.
///
/// Weeks and days are nominal: a day is one calendar day and may be 23 or 25 hours
/// long across a daylight saving transition. Hours, minutes and seconds are exact.
///
/// See more in [RFC 5545](
/// https://www.rfc-editor.org/rfc/rfc5545#section-3.3.6)
public struct ICDuration: Equatable {

    public var isNegative: Bool
    public var weeks: Int
    public var days: Int
    public var hours: Int
    public var minutes: Int
    public var seconds: Int

    public init(
        isNegative: Bool = false,
        weeks: Int = 0,
        days: Int = 0,
        hours: Int = 0,
        minutes: Int = 0,
        seconds: Int = 0
    ) {
        self.isNegative = isNegative
        self.weeks = weeks
        self.days = days
        self.hours = hours
        self.minutes = minutes
        self.seconds = seconds
    }

    /// Nominal days (weeks and days), negative for a negative duration
    public var nominalDays: Int {
        (weeks * 7 + days) * (isNegative ? -1 : 1)
    }

    /// Exact seconds (hours, minutes and seconds), negative for a negative duration
    public var exactSeconds: Int {
        (hours * 3_600 + minutes * 60 + seconds) * (isNegative ? -1 : 1)
    }

    /// The duration in seconds, counting a day as 24 hours
    public var timeInterval: TimeInterval {
        TimeInterval(nominalDays * 86_400 + exactSeconds)
    }

    /// Parses a `DURATION` value such as `P15DT5H0M20S`, `P7W` or `-PT15M`
    public init?(_ value: String) {
        var characters = Substring(value)
        let isNegative = characters.first == "-"
        if characters.first == "-" || characters.first == "+" {
            characters = characters.dropFirst()
        }

        guard characters.first == "P", characters.count > 1 else {
            return nil
        }

        var components = [Character: Int]()
        var isTime = false
        var number = ""

        for character in characters.dropFirst() {
            if character.isASCII, character.isNumber {
                number.append(character)
            } else if character == "T", !isTime, number.isEmpty {
                isTime = true
            } else {
                // Designators are case-insensitive; M means months only before T, which DURATION does not allow
                let designator = Character(character.uppercased())
                let allowed: Set<Character> = isTime ? ["H", "M", "S"] : ["W", "D"]
                guard
                    allowed.contains(designator),
                    let amount = Int(number),
                    components[isTime && designator == "M" ? "m" : designator] == nil
                else { return nil }
                components[isTime && designator == "M" ? "m" : designator] = amount
                number = ""
            }
        }

        let hasTime = components.keys.contains { ["H", "m", "S"].contains($0) }
        guard number.isEmpty, !components.isEmpty, isTime == hasTime else {
            return nil
        }

        self.init(
            isNegative: isNegative,
            weeks: components["W"] ?? 0,
            days: components["D"] ?? 0,
            hours: components["H"] ?? 0,
            minutes: components["m"] ?? 0,
            seconds: components["S"] ?? 0
        )
    }
}
