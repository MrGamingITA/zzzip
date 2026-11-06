import Foundation

struct ArchiveEntry: Equatable {
    let path: String
    let isFolder: Bool
    let size: UInt64?
    let packedSize: UInt64?
    let modified: Date?
    let isEncrypted: Bool
    let method: String?
}

struct ArchiveInfo {
    let type: String
    let physicalSize: UInt64?
    let isMultiVolume: Bool
    let volumeCount: Int?
    let hasEncryptedEntries: Bool
    let entries: [ArchiveEntry]
}
