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
        // Separators are ASCII, so the UTF-8 bytes can be scanned without decoding characters
        guard let separatorByte = separator.asciiValue else {
            return [self[...]]
        }

        let quote = UInt8(ascii: "\"")
        var parts = [Substring]()
        var start = startIndex
        var isQuoted = false
        var index = utf8.startIndex

        while index < utf8.endIndex {
            let byte = utf8[index]
            if byte == quote {
                isQuoted.toggle()
            } else if byte == separatorByte, !isQuoted, parts.count < maxSplits {
                parts.append(self[start..<index])
                start = utf8.index(after: index)
            }
            index = utf8.index(after: index)
        }

        parts.append(self[start...])
        return parts
    }
}
