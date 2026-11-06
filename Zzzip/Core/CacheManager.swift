import Foundation

final class CacheManager {
    static let shared = CacheManager()
    let root: URL

    init(root: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Zzzip", isDirectory: true)) {
        self.root = root
    }

    func makeSession() -> URL {
        let u = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    func remove(session: URL) { try? FileManager.default.removeItem(at: session) }

    func purgeAll() {
        for u in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
            try? FileManager.default.removeItem(at: u)
        }
    }
}
