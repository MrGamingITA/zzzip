import Foundation

final class CancelToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var handlers: [() -> Void] = []

    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }

    func cancel() {
        lock.lock()
        guard !cancelled else { lock.unlock(); return }
        cancelled = true
        let hs = handlers; handlers = []
        lock.unlock()
        hs.forEach { $0() }
    }

    /// Registers a handler; runs immediately if already cancelled.
    func onCancel(_ h: @escaping () -> Void) {
        lock.lock()
        if cancelled { lock.unlock(); h(); return }
        handlers.append(h); lock.unlock()
    }
}
