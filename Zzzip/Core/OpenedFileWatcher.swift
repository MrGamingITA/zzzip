import Foundation

/// Remembers files opened from the cache and reports those changed on disk since.
final class OpenedFileWatcher {
    private struct Stamp: Equatable { let date: Date?; let size: Int? }
    private var tracked: [URL: (internalPath: String, stamp: Stamp)] = [:]

    private func stamp(_ u: URL) -> Stamp {
        let v = try? u.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        return Stamp(date: v?.contentModificationDate, size: v?.fileSize)
    }

    func track(file: URL, internalPath: String) {
        var u = file; u.removeAllCachedResourceValues()
        tracked[file] = (internalPath, stamp(u))
    }

    func modifiedFiles() -> [(file: URL, internalPath: String)] {
        tracked.compactMap { (url, v) in
            var u = url; u.removeAllCachedResourceValues()
            guard FileManager.default.fileExists(atPath: u.path) else { return nil }
            return stamp(u) != v.stamp ? (url, v.internalPath) : nil
        }.sorted { $0.internalPath < $1.internalPath }
    }

    func markSynced(_ file: URL) {
        guard let v = tracked[file] else { return }
        var u = file; u.removeAllCachedResourceValues()
        tracked[file] = (v.internalPath, stamp(u))
    }
}
