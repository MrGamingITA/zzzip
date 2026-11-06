import Foundation

enum ConflictDecision: String, Codable { case replace, skip, keepBoth }

struct ConflictAnswer: Equatable {
    var decision: ConflictDecision
    var applyToAll: Bool
}

final class Extractor {
    let engine: SevenZip
    let fm = FileManager.default

    init(engine: SevenZip) { self.engine = engine }

    /// Extracts `items` (empty = whole archive) into `destination`, following the smart-folder rule.
    /// Returns the top-level URLs created.
    /// `namedAfter`: the archive the user sees (e.g. the .tar.gz), used to name the container folder.
    func extract(archive: URL, items: [ArchiveNode], destination: URL, mode: ExtractionMode, password: String?,
                 namedAfter: URL? = nil,
                 onConflict: @escaping (URL) async -> ConflictAnswer,
                 progress: ((Double) -> Void)? = nil, cancel: CancelToken? = nil) async throws -> [URL] {
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        let staging = destination.appendingPathComponent(".zzzip-staging-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: staging) }

        let items = ArchiveNode.removingDescendants(items)
        try await engine.extract(archive, items: items.map(\.archivePath), to: staging, password: password, progress: progress, cancel: cancel)
        if cancel?.isCancelled == true { throw EngineError.cancelled }

        let stagingRoot = staging.resolvingSymlinksInPath().path + "/"
        var sources: [URL]
        if items.isEmpty {
            sources = try fm.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil, options: [])
        } else {
            sources = items.map { staging.appendingPathComponent(ArchiveTree.components($0.archivePath).joined(separator: "/")) }
        }
        // Zip-slip guard: only move what really sits inside the staging folder.
        sources = sources.filter { src in
            UniqueName.exists(src, fm: fm) && src.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(stagingRoot)
        }

        if !items.isEmpty && sources.isEmpty {
            throw EngineError.failed(code: 0, message: String(localized: "Nothing could be extracted from the selected items."))
        }

        var target = destination
        if let container = ExtractionPlanner.containerFolder(archiveURL: namedAfter ?? archive, topLevelCount: sources.count, destination: destination, mode: mode, fm: fm) {
            try fm.createDirectory(at: container, withIntermediateDirectories: false)
            target = container
        }

        var remembered: ConflictDecision?
        var created: [URL] = []
        for src in sources {
            var dst = target.appendingPathComponent(src.lastPathComponent)
            if UniqueName.exists(dst, fm: fm) {
                let decision: ConflictDecision
                if let r = remembered { decision = r } else {
                    let a = await onConflict(dst)
                    if a.applyToAll { remembered = a.decision }
                    decision = a.decision
                }
                switch decision {
                case .skip: continue
                case .keepBoth: dst = UniqueName.next(for: dst, fm: fm)
                case .replace:
                    _ = try fm.replaceItemAt(dst, withItemAt: src)
                    created.append(dst); continue
                }
            }
            try fm.moveItem(at: src, to: dst)
            created.append(dst)
        }
        return target == destination ? created : [target]
    }
}
