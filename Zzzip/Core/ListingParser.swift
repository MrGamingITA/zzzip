import Foundation

enum ListingParserError: Error { case noListing }

/// Parses the technical listing printed by `7zz l -slt` (without `-ba`).
enum ListingParser {
    /// Name for an entry the format doesn't name (xz, bzip2…): the archive name minus its compression extension.
    static func impliedName(archiveName: String) -> String {
        let ns = archiveName as NSString
        let ext = ns.pathExtension.lowercased(), base = ns.deletingPathExtension
        if ["tgz", "tbz", "tbz2", "txz", "tzst", "taz", "tlz"].contains(ext) { return base + ".tar" }
        return base.isEmpty ? archiveName : base
    }

    static func parse(_ stdout: String, archiveName: String = "") throws -> ArchiveInfo {
        var archiveProps: [String: String] = [:]
        var entries: [ArchiveEntry] = []
        var current: [String: String] = [:]
        var section = 0 // 0 = preamble, 1 = archive props (after "--"), 2 = entries (after "----------")

        func flush() {
            guard !current.isEmpty, let path = current["Path"] ?? (current["Size"] != nil ? impliedName(archiveName: archiveName) : nil) else { current = [:]; return }
            let attrs = current["Attributes"] ?? ""
            let folder = current["Folder"] == "+" || attrs.hasPrefix("D")
            entries.append(ArchiveEntry(
                path: path,
                isFolder: folder,
                size: current["Size"].flatMap { UInt64($0) },
                packedSize: current["Packed Size"].flatMap { UInt64($0) },
                modified: current["Modified"].flatMap(parseDate),
                isEncrypted: current["Encrypted"] == "+",
                method: current["Method"].flatMap { $0.isEmpty ? nil : $0 }))
            current = [:]
        }

        stdout.enumerateLines { raw, _ in
            let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
            if section < 2 && line == "----------" { section = 2; return }
            if section == 0 && line == "--" { section = 1; return }
            guard section > 0 else { return }
            if line.isEmpty { if section == 2 { flush() }; return }
            guard let r = line.range(of: " = ") ?? (line.hasSuffix(" =") ? line.range(of: " =", options: .backwards) : nil) else { return }
            let key = String(line[..<r.lowerBound])
            let value = String(line[r.upperBound...])
            if section == 1 { archiveProps[key] = value } else { current[key] = value }
        }
        if section == 2 { flush() }
        guard section == 2 || archiveProps["Type"] != nil else { throw ListingParserError.noListing }

        return ArchiveInfo(
            type: archiveProps["Type"] ?? "",
            physicalSize: archiveProps["Physical Size"].flatMap { UInt64($0) },
            isMultiVolume: archiveProps["Multivolume"] == "+" || (archiveProps["Volumes"].flatMap { Int($0) } ?? 1) > 1,
            volumeCount: archiveProps["Volumes"].flatMap { Int($0) },
            hasEncryptedEntries: entries.contains { $0.isEncrypted },
            entries: entries)
    }

    private static let calendar: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = .current; return c }()

    /// `yyyy-MM-dd HH:mm:ss(.fffffff)?`, local time.
    static func parseDate(_ s: String) -> Date? {
        let u = Array(s.utf8)
        guard u.count >= 19 else { return nil }
        func num(_ a: Int, _ b: Int) -> Int? {
            var v = 0
            for i in a..<b { let c = u[i]; guard c >= 48 && c <= 57 else { return nil }; v = v * 10 + Int(c - 48) }
            return v
        }
        guard let y = num(0, 4), let mo = num(5, 7), let d = num(8, 10), let h = num(11, 13), let mi = num(14, 16), let se = num(17, 19) else { return nil }
        var frac = 0.0
        if u.count > 20, u[19] == 46, let f = num(20, u.count) { frac = Double(f) / pow(10, Double(u.count - 20)) }
        let comps = DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: se)
        return calendar.date(from: comps).map { $0.addingTimeInterval(frac) }
    }
}
