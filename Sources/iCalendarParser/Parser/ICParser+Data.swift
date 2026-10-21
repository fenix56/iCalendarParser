import Foundation

// MARK: - Data input

extension ICParser {

    /// Parses iCalendar data, as downloaded or read from a file. Returns nil if not found.
    ///
    /// Prefer this to converting the data to a `String` first. RFC 5545 allows a producer to fold a
    /// line in the middle of a multi-byte UTF-8 character, such as an emoji; then `String(data:encoding:)`
    /// fails for the whole file. Here lines are unfolded before they are decoded, which restores the
    /// character. Invalid UTF-8 is replaced with U+FFFD.
    ///
    /// See more in [RFC 5545](
    /// https://www.rfc-editor.org/rfc/rfc5545#section-3.1)
    public func calendar(
        from data: Data
    ) -> ICalendar? {
        parseCalendar(
            elements: ContentLineScanner.properties(in: data, checkCancellation: {}),
            checkCancellation: {}
        )
    }

    /// Parses iCalendar data, as downloaded or read from a file. Returns nil if not found.
    ///
    /// Works like `calendar(from:)`, and calls `isCancelled` regularly while parsing.
    /// Throws `CancellationError` as soon as it returns `true`:
    ///
    /// ```swift
    /// let calendar = try parser.calendar(from: data) { Task.isCancelled }
    /// ```
    public func calendar(
        from data: Data,
        isCancelled: () -> Bool
    ) throws -> ICalendar? {
        func checkCancellation() throws {
            if isCancelled() {
                throw CancellationError()
            }
        }

        return try parseCalendar(
            elements: ContentLineScanner.properties(in: data, checkCancellation: checkCancellation),
            checkCancellation: checkCancellation
        )
    }
}
