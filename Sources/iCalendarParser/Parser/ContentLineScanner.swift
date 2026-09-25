import Foundation

/// Splits iCalendar text into properties by scanning its UTF-8 bytes.
///
/// Every character with a meaning in the content line format (line breaks, `:`, `"`, space and tab)
/// is ASCII, and ASCII bytes never occur inside a multi-byte UTF-8 sequence, so the text can be split
/// on bytes without decoding characters. This is much faster than working with `Character`s.
///
/// - Accepts CRLF, LF and CR line endings.
/// - A line starting with a space or a horizontal tab continues the previous line.
/// - A line is split into name and value at the first `:` outside a quoted parameter value.
/// - Lines without a name or a value are skipped, and a leading byte order mark is ignored.
///
/// See more in [RFC 5545](
/// https://www.rfc-editor.org/rfc/rfc5545#section-3.1)
enum ContentLineScanner {

    private static let lineFeed = UInt8(ascii: "\n")
    private static let carriageReturn = UInt8(ascii: "\r")
    private static let space = UInt8(ascii: " ")
    private static let tab = UInt8(ascii: "\t")
    private static let colon = UInt8(ascii: ":")
    private static let quote = UInt8(ascii: "\"")
    private static let byteOrderMark: [UInt8] = [0xEF, 0xBB, 0xBF]

    /// Calls `checkCancellation` once per physical line
    static func properties(
        in text: String,
        checkCancellation: () throws -> Void
    ) rethrows -> [ICProperty] {
        var text = text
        text.makeContiguousUTF8()

        if let properties = try text.utf8.withContiguousStorageIfAvailable({ bytes in
            try properties(in: bytes, checkCancellation: checkCancellation)
        }) {
            return properties
        }

        // Not reached for a contiguous string; kept as a safe fallback
        return try Array(text.utf8).withUnsafeBufferPointer { bytes in
            try properties(in: bytes, checkCancellation: checkCancellation)
        }
    }

    private static func properties(
        in bytes: UnsafeBufferPointer<UInt8>,
        checkCancellation: () throws -> Void
    ) rethrows -> [ICProperty] {
        var properties = [ICProperty]()
        properties.reserveCapacity(bytes.count / 48)

        // The current logical line: a range of `bytes`, or `unfolded` once a continuation line was added
        var current: Range<Int>?
        var unfolded = [UInt8]()
        var isUnfolded = false

        func finishLine() {
            if isUnfolded {
                unfolded.withUnsafeBufferPointer { line in
                    if let property = property(in: line[...]) {
                        properties.append(property)
                    }
                }
            } else if let current, let property = property(in: bytes[current]) {
                properties.append(property)
            }
        }

        var lineStart = bytes.starts(with: byteOrderMark) ? byteOrderMark.count : 0
        var index = lineStart

        while lineStart <= bytes.count {
            // Find the end of the physical line
            while index < bytes.count, bytes[index] != lineFeed, bytes[index] != carriageReturn {
                index += 1
            }
            let line = lineStart..<index

            try checkCancellation()

            let isContinuation = !line.isEmpty
                && (bytes[line.lowerBound] == space || bytes[line.lowerBound] == tab)
                && (current != nil || isUnfolded)

            if isContinuation {
                if !isUnfolded, let current {
                    unfolded.removeAll(keepingCapacity: true)
                    unfolded.append(contentsOf: bytes[current])
                    isUnfolded = true
                }
                unfolded.append(contentsOf: bytes[(line.lowerBound + 1)..<line.upperBound])
            } else {
                finishLine()
                current = line
                isUnfolded = false
            }

            guard index < bytes.count else {
                break
            }
            index = afterLineBreak(at: index, in: bytes)
            lineStart = index
        }

        finishLine()
        return properties
    }

    /// The position after the line break at `index`: CRLF, LF or CR
    private static func afterLineBreak(at index: Int, in bytes: UnsafeBufferPointer<UInt8>) -> Int {
        if bytes[index] == carriageReturn, index + 1 < bytes.count, bytes[index + 1] == lineFeed {
            return index + 2
        }
        return index + 1
    }

    /// Splits a logical line at the first `:` outside quotes
    private static func property(in line: Slice<UnsafeBufferPointer<UInt8>>) -> ICProperty? {
        var isQuoted = false
        for index in line.indices {
            let byte = line[index]
            if byte == quote {
                isQuoted.toggle()
            } else if byte == colon, !isQuoted {
                guard index > line.startIndex, index + 1 < line.endIndex else {
                    return nil
                }
                // The bytes are valid UTF-8 split at ASCII characters, so decoding cannot fail
                // swiftlint:disable optional_data_string_conversion
                return (
                    name: String(decoding: line[line.startIndex..<index], as: UTF8.self),
                    value: String(decoding: line[(index + 1)..<line.endIndex], as: UTF8.self)
                )
                // swiftlint:enable optional_data_string_conversion
            }
        }
        return nil
    }
}
