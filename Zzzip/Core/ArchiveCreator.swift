import AppKit

enum CreateFormat: String, CaseIterable, Codable {
    case zip, sevenZip = "7z", tar, tarGz = "tar.gz", tarBz2 = "tar.bz2", tarXz = "tar.xz"

    var fileExtension: String { rawValue }
    var supportsPassword: Bool { self == .zip || self == .sevenZip }
    var supportsEncryptedNames: Bool { self == .sevenZip }
    var supportsLevel: Bool { self != .tar }
    /// 7zz type for the outer compressor of a tar pipeline.
    var compressorType: String? {
        switch self { case .tarGz: return "gzip"; case .tarBz2: return "bzip2"; case .tarXz: return "xz"; default: return nil }
    }
    var displayName: String {
        switch self { case .zip: return "ZIP"; case .sevenZip: return "7z"; case .tar: return "TAR"
        case .tarGz: return "TAR.GZ"; case .tarBz2: return "TAR.BZ2"; case .tarXz: return "TAR.XZ" }
    }
}

enum CompressionLevel: Int, CaseIterable, Codable {
    case none = 0, fast = 1, normal = 5, maximum = 7, ultra = 9

    var title: String {
        switch self {
        case .none: return String(localized: "None")
        case .fast: return String(localized: "Fast")
        case .normal: return String(localized: "Normal")
        case .maximum: return String(localized: "Maximum")
        case .ultra: return String(localized: "Ultra")
        }
    }
}

struct CreateOptions: Codable, Equatable {
    var name: String
    var destination: URL
    var format: CreateFormat = .zip
    var level: CompressionLevel = .normal
    var password: String? = nil
    var encryptNames = false
    var volumeSize: UInt64? = nil
    var excludeMacFiles = true
    var trashOriginals = false
}

final class ArchiveCreator {
    let engine: SevenZip
    let fm = FileManager.default

    init(engine: SevenZip) { self.engine = engine }

    static func defaultName(for sources: [URL]) -> String {
        guard sources.count == 1, let s = sources.first else { return String(localized: "Archive") }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: s.path, isDirectory: &isDir), isDir.boolValue { return s.lastPathComponent }
        return s.pathExtension.isEmpty ? s.lastPathComponent : s.deletingPathExtension().lastPathComponent
    }

    static let macExclusions = ["-xr!.DS_Store", "-xr!__MACOSX", "-xr!._*"]

    /// `-spd` (no wildcards in names) also disables the wildcard in `-xr!._*`, so use it only when a path really contains wildcard characters.
    static func needsLiteralNames(_ sources: [String]) -> Bool { sources.contains { $0.contains { "*?[".contains($0) } } }

    /// One 7zz command, or two to be piped (tar → compressor) for `tar.*`.
    static func arguments(output: URL, sources: [String], options o: CreateOptions) -> [[String]] {
        let excl = o.excludeMacFiles ? macExclusions : []
        let spd = needsLiteralNames(sources) ? ["-spd"] : []
        let vol = o.volumeSize.map { ["-v\($0)b"] } ?? []
        var pw: [String] = []
        if let p = o.password, !p.isEmpty, o.format.supportsPassword {
            pw = ["-p\(p)"]
            if o.format == .zip { pw.append("-mem=AES256") }
            if o.format == .sevenZip && o.encryptNames { pw.append("-mhe=on") }
        }
        if let comp = o.format.compressorType {
            let tarName = UniqueName.split(output.lastPathComponent).base + ".tar"
            return [["a", "-ttar", "-so", "-an"] + spd + excl + ["--"] + sources,
                    ["a", "-t\(comp)", "-si\(tarName)", "-mx\(o.level.rawValue)"] + vol + [output.path]]
        }
        let type = o.format == .sevenZip ? "7z" : o.format.rawValue
        let level = o.format.supportsLevel ? ["-mx\(o.level.rawValue)"] : []
        return [["a", "-t\(type)", output.path] + level + ["-bsp1", "-bb0"] + spd + excl + pw + vol + ["--"] + sources]
    }

    /// Creates the archive in a staging folder inside the destination, then moves it into place.
    /// Returns the URL of the archive (the `.001` volume when split).
    func create(sources: [URL], options: CreateOptions, progress: ((Double) -> Void)? = nil, cancel: CancelToken? = nil) async throws -> URL {
        guard !sources.isEmpty else { throw EngineError.failed(code: -1, message: "") }
        try fm.createDirectory(at: options.destination, withIntermediateDirectories: true)
        let staging = options.destination.appendingPathComponent(".zzzip-staging-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: staging) }

        let fileName = "\(options.name).\(options.format.fileExtension)"
        let stagedOut = staging.appendingPathComponent(fileName)
        // Absolute paths: 7zz stores each source by its last component, so sources may come from different folders.
        let cmds = Self.arguments(output: stagedOut, sources: sources.map(\.path), options: options)
        let name = fileName

        if cmds.count == 2 {
            let pipe = Pipe()
            async let producer: Void = { _ = try await self.engine.run(cmds[0], stdoutTo: pipe.fileHandleForWriting, cancel: cancel, failOnWarning: true, archiveName: name) }()
            async let consumer: Void = { _ = try await self.engine.run(cmds[1], stdinFrom: pipe.fileHandleForReading, cancel: cancel, failOnWarning: true, archiveName: name) }()
            do { try await producer } catch { try? pipe.fileHandleForWriting.close(); _ = try? await consumer; throw error }
            try? pipe.fileHandleForWriting.close()
            try await consumer
            progress?(1)
        } else {
            try await engine.run(cmds[0], progress: progress, cancel: cancel, failOnWarning: true, archiveName: name)
        }

        // Move everything produced (single file or volumes) next to each other, avoiding collisions.
        let produced = try fm.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil).sorted { $0.lastPathComponent < $1.lastPathComponent }
        var final = options.destination.appendingPathComponent(fileName)
        if produced.count == 1 {
            final = UniqueName.next(for: final, fm: fm)
            try fm.moveItem(at: produced[0], to: final)
        } else {
            // Volumes: pick a base name free for every volume.
            var base = fileName, i = 2
            while produced.contains(where: { UniqueName.exists(options.destination.appendingPathComponent($0.lastPathComponent.replacingOccurrences(of: fileName, with: base)), fm: fm) }) {
                base = "\(options.name) \(i).\(options.format.fileExtension)"; i += 1
            }
            for p in produced { try fm.moveItem(at: p, to: options.destination.appendingPathComponent(p.lastPathComponent.replacingOccurrences(of: fileName, with: base))) }
            final = options.destination.appendingPathComponent(base + ".001")
        }
        if options.trashOriginals {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                NSWorkspace.shared.recycle(sources) { _, _ in c.resume() }
            }
        }
        return final
    }
}
