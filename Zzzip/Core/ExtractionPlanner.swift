import Foundation

enum UniqueName {
    static let doubleExtensions = ["tar.gz", "tar.bz2", "tar.xz", "tar.zst", "tar.lz4", "tar.z"]

    static func split(_ name: String) -> (base: String, ext: String) {
        let lower = name.lowercased()
        for d in doubleExtensions where lower.hasSuffix("." + d) && lower.count > d.count + 1 {
            return (String(name.dropLast(d.count + 1)), String(name.suffix(d.count)))
        }
        let ns = name as NSString
        let ext = ns.pathExtension
        return ext.isEmpty || ns.deletingPathExtension.isEmpty ? (name, "") : (ns.deletingPathExtension, ext)
    }

    static func exists(_ url: URL, fm: FileManager) -> Bool {
        (try? fm.attributesOfItem(atPath: url.path)) != nil
    }

    /// `name.ext` if free, else `name 2.ext`, `name 3.ext`…
    static func next(for url: URL, fm: FileManager = .default) -> URL {
        guard exists(url, fm: fm) else { return url }
        let dir = url.deletingLastPathComponent()
        let (base, ext) = split(url.lastPathComponent)
        var i = 2
        while true {
            let candidate = dir.appendingPathComponent(ext.isEmpty ? "\(base) \(i)" : "\(base) \(i).\(ext)")
            if !exists(candidate, fm: fm) { return candidate }
            i += 1
        }
    }
}

enum ExtractionMode { case smart, loose }

enum ExtractionPlanner {
    static let archiveExtensions: Set<String> = ["zip", "7z", "rar", "tar", "gz", "tgz", "bz2", "tbz", "tbz2", "xz", "txz", "zst", "tzst",
                                                  "iso", "cab", "wim", "lzh", "lha", "arj", "cpio", "xar", "pkg", "dmg", "zipx", "lz4", "z"]

    /// Archive name without archive and volume extensions: `x.tar.gz` → `x`, `x.part1.rar` → `x`, `x.7z.001` → `x`.
    static func baseName(of url: URL) -> String {
        var name = url.lastPathComponent
        if let r = name.range(of: #"\.part\d+\.rar$"#, options: [.regularExpression, .caseInsensitive]) { return String(name[..<r.lowerBound]) }
        if let r = name.range(of: #"\.(\d{3})$"#, options: .regularExpression) { name = String(name[..<r.lowerBound]) }
        while true {
            let ext = (name as NSString).pathExtension.lowercased()
            let stripped = (name as NSString).deletingPathExtension
            guard archiveExtensions.contains(ext), !stripped.isEmpty else { break }
            name = stripped
        }
        return name
    }

    /// nil → items go straight into `destination`; otherwise the new container folder to create.
    static func containerFolder(archiveURL: URL, topLevelCount: Int, destination: URL, mode: ExtractionMode,
                                fm: FileManager = .default) -> URL? {
        guard mode == .smart, topLevelCount > 1 else { return nil }
        return UniqueName.next(for: destination.appendingPathComponent(baseName(of: archiveURL)), fm: fm)
    }
}
