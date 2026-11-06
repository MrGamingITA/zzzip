import Foundation

/// Runs async jobs strictly one after another (used for drag-out file promises of one window).
actor SerialRunner {
    private var tail: Task<Void, Never>?

    func run<T>(_ job: @escaping @Sendable () async throws -> T) async throws -> T {
        let previous = tail
        let task = Task<T, Error> {
            await previous?.value
            return try await job()
        }
        tail = Task { _ = try? await task.value }
        return try await task.value
    }
}
