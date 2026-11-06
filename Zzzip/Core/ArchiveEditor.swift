import Foundation

/// Edits archives safely: 7zz works on a sibling copy that replaces the original only on success.
final class ArchiveEditor {
    let engine: SevenZip
    let fm = FileManager.default

    init(engine: SevenZip) { self.engine = engine }

    func add(files: [URL], intoFolder: String, archive: URL, password: String?, encryptHeaders: Bool = false,
             progress: ((Double) -> Void)? = nil, cancel: CancelToken? = nil) async throws {
        let stage = fm.temporaryDirectory.appendingPathComponent("zzzip-add-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: stage) }
        let folderComps = ArchiveTree.components(intoFolder)
        let inner = folderComps.reduce(stage) { $0.appendingPathComponent($1) }
        try fm.createDirectory(at: inner, withIntermediateDirectories: true)
        var relative: [String] = []
        for f in files {
            try fm.copyItem(at: f, to: inner.appendingPathComponent(f.lastPathComponent))
            relative.append((folderComps + [f.lastPathComponent]).joined(separator: "/"))
        }
        try await withSafeCopy(of: archive) { copy in
            try await self.engine.run(["a", copy.path, "-bsp1", "-bb0", "-spd"] + self.writeArgs(archive: archive, password: password, encryptHeaders: encryptHeaders)
                                      + ["--"] + relative,
                                      cwd: stage, progress: progress, cancel: cancel, archiveName: archive.lastPathComponent)
        }
    }

    func delete(paths: [String], archive: URL, password: String?, cancel: CancelToken? = nil) async throws {
        try await withSafeCopy(of: archive) { copy in
            try await self.engine.run(["d", copy.path, "-spd"] + SevenZip.passwordArgs(password) + ["--"] + paths,
                                      cancel: cancel, archiveName: archive.lastPathComponent)
            // 7zz exits 0 even when it matched nothing (e.g. "./"-prefixed tar entries): check before swapping in.
            let left = Set(try await self.engine.list(copy, password: password).entries.map { ArchiveTree.components($0.path).joined(separator: "/") })
            let still = paths.map { ArchiveTree.components($0).joined(separator: "/") }.filter(left.contains)
            if !still.isEmpty {
                throw EngineError.failed(code: 0, message: String(localized: "These items can't be deleted from this archive: \(still.joined(separator: ", "))"))
            }
        }
    }

    func update(file: URL, internalPath: String, archive: URL, password: String?, encryptHeaders: Bool = false) async throws {
        var comps = ArchiveTree.components(internalPath)
        let name = comps.removeLast()
        let stage = fm.temporaryDirectory.appendingPathComponent("zzzip-upd-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: stage) }
        let inner = comps.reduce(stage) { $0.appendingPathComponent($1) }
        try fm.createDirectory(at: inner, withIntermediateDirectories: true)
        try fm.copyItem(at: file, to: inner.appendingPathComponent(name))
        try await withSafeCopy(of: archive) { copy in
            try await self.engine.run(["u", copy.path, "-spd"] + self.writeArgs(archive: archive, password: password, encryptHeaders: encryptHeaders)
                                      + ["--", (comps + [name]).joined(separator: "/")],
                                      cwd: stage, archiveName: archive.lastPathComponent)
        }
    }

    private func writeArgs(archive: URL, password: String?, encryptHeaders: Bool) -> [String] {
        guard let password else { return [] }
        var a = ["-p\(password)"]
        let ext = archive.pathExtension.lowercased()
        if ext == "zip" { a.append("-mem=AES256") }
        if ext == "7z" && encryptHeaders { a.append("-mhe=on") }
        return a
    }

    /// Runs `op` on a copy next to the original (same volume, keeps extension), then swaps it in.
    private func withSafeCopy(of archive: URL, _ op: (URL) async throws -> Void) async throws {
        let dir = archive.deletingLastPathComponent()
        let ext = archive.pathExtension
        let copy = dir.appendingPathComponent(".\(archive.deletingPathExtension().lastPathComponent).zzzip-\(UUID().uuidString)" + (ext.isEmpty ? "" : ".\(ext)"))
        try fm.copyItem(at: archive, to: copy)
        do {
            try await op(copy)
            _ = try fm.replaceItemAt(archive, withItemAt: copy)
        } catch {
            try? fm.removeItem(at: copy)
            throw error
        }
    }
}
