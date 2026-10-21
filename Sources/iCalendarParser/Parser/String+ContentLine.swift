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
        separator: Character
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
            } else if byte == separatorByte, !isQuoted {
                parts.append(self[start..<index])
                start = utf8.index(after: index)
            }
            index = utf8.index(after: index)
        }

        parts.append(self[start...])
        return parts
    }

    /// Whether this property name, which may be followed by parameters, is `name`.
    ///
    /// Property names are upper-cased when parsed, so `name` must be upper case.
    func hasPropertyName(_ name: String) -> Bool {
        let bytes = utf8
        guard bytes.starts(with: name.utf8) else {
            return false
        }
        let next = bytes.index(bytes.startIndex, offsetBy: name.utf8.count)
        return next == bytes.endIndex || bytes[next] == UInt8(ascii: ";")
    }

    /// The property name without parameters, e.g. `X-ALT-DESC` for `X-ALT-DESC;FMTTYPE=text/html`
    var propertyBaseName: String {
        guard let end = utf8.firstIndex(of: UInt8(ascii: ";")) else {
            return self
        }
        return String(self[..<end])
    }

    /// Upper case, for names and enumerated values, which compare case-insensitively.
    ///
    /// See more in [RFC 5545](
    /// https://www.rfc-editor.org/rfc/rfc5545#section-2.1)
    var normalizedName: String {
        utf8.contains { (UInt8(ascii: "a")...UInt8(ascii: "z")).contains($0) } ? uppercased() : self
    }
}
