import Foundation

/// Compressed tarballs (.tar.gz, .tgz, .tar.xz…) list as a single `.tar` entry in 7zz.
/// To browse their real contents we decompress the inner tar into a cache folder and work on that.
enum InnerTar {
    static let compressorTypes: Set<String> = ["gzip", "bzip2", "xz", "zstd", "lz4", "z", "lzip"]

    static func resolve(archive: URL, info: ArchiveInfo, engine: SevenZip, cacheDir: URL,
                        cancel: CancelToken? = nil) async throws -> URL? {
        guard compressorTypes.contains(info.type.lowercased()), info.entries.count == 1,
              let only = info.entries.first, !only.isFolder else { return nil }
        let name = archive.lastPathComponent.lowercased()
        let looksTar = only.path.lowercased().hasSuffix(".tar")
            || [".tgz", ".tbz", ".tbz2", ".txz", ".tzst", ".taz"].contains { name.hasSuffix($0) }
        guard looksTar else { return nil }
        let dir = cacheDir.appendingPathComponent("inner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try await engine.extract(archive, items: [], to: dir, password: nil, cancel: cancel)
        guard let produced = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).first else { return nil }
        // Make sure 7zz recognises it as tar (by extension too).
        let tar = produced.pathExtension.lowercased() == "tar" ? produced : produced.appendingPathExtension("tar")
        if tar != produced { try FileManager.default.moveItem(at: produced, to: tar) }
        return tar
    }
}
