import AppKit
import UniformTypeIdentifiers

enum Fmt {
    static func bytes(_ v: UInt64) -> String { ByteCountFormatter.string(fromByteCount: Int64(clamping: v), countStyle: .file) }

    static let date: DateFormatter = { let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f }()

    static func utType(for node: ArchiveNode) -> UTType? {
        node.isFolder ? .folder : UTType(filenameExtension: (node.name as NSString).pathExtension)
    }

    static func kind(_ node: ArchiveNode) -> String {
        if node.isFolder { return String(localized: "Folder") }
        return utType(for: node)?.localizedDescription ?? String(localized: "Document")
    }

    private static var iconCache: [String: NSImage] = [:]
    static func icon(_ node: ArchiveNode) -> NSImage {
        let key = node.isFolder ? "/folder" : (node.name as NSString).pathExtension.lowercased()
        if let i = iconCache[key] { return i }
        let i = NSWorkspace.shared.icon(for: utType(for: node) ?? .data)
        iconCache[key] = i
        return i
    }
}

enum AppIcon {
    /// The icon straight from the app's asset catalog (never a stale system-cached copy or the generic placeholder).
    static var image: NSImage { NSImage(named: "AppIcon") ?? NSApp.applicationIconImage }
}
