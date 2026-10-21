/// Throws `CancellationError` when `isCancelled` returns `true`.
///
/// Turns the `isCancelled` closure of the public cancellable methods into the throwing check they use inside.
func throwIfCancelled(_ isCancelled: () -> Bool) throws {
    if isCancelled() {
        throw CancellationError()
    }
}
