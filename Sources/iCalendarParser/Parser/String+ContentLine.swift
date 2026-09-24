import Foundation

extension String {

    /// Splits the string at `separator`, ignoring separators inside DQUOTE-quoted sections.
    ///
    /// Parameter values may contain `:`, `;` and `,` when quoted, e.g.
    /// `ORGANIZER;SENT-BY="mailto:a@example.com":mailto:b@example.com`.
    ///
    /// See more in [RFC 5545](
    /// https://www.rfc-editor.org/rfc/rfc5545#section-3.2)
    func splitOutsideQuotes(
        separator: Character,
        maxSplits: Int = .max
    ) -> [Substring] {
        var parts = [Substring]()
        var start = startIndex
        var isQuoted = false
        var index = startIndex

        while index < endIndex {
            let character = self[index]
            if character == "\"" {
                isQuoted.toggle()
            } else if character == separator, !isQuoted, parts.count < maxSplits {
                parts.append(self[start..<index])
                start = self.index(after: index)
            }
            index = self.index(after: index)
        }

        parts.append(self[start...])
        return parts
    }
}
