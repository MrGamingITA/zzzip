import Foundation

enum FormatCapabilities {
    /// Only formats 7zz can update in place: zip, 7z, wim and uncompressed tar. Never multi-volume.
    static func isWritable(info: ArchiveInfo, url: URL) -> Bool {
        guard !info.isMultiVolume else { return false }
        // 7zz can't write "./name" or "/name" entries back correctly: such archives stay read-only.
        if info.entries.contains(where: { $0.path.hasPrefix("./") || $0.path.hasPrefix("/") || $0.path == "." }) { return false }
        switch info.type.lowercased() {
        case "zip", "7z", "wim": return true
        case "tar": return url.pathExtension.lowercased() == "tar"
        default: return false
        }
    }
}

extension FormatCapabilities {
    /// Writing to an archive that already has encrypted entries without knowing the password would add unencrypted files.
    static func needsPasswordBeforeWriting(info: ArchiveInfo, password: String?) -> Bool {
        info.hasEncryptedEntries && (password ?? "").isEmpty
    }
}
