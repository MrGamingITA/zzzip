import Foundation

struct SupportedType: Hashable {
    let identifier: String
    let extensions: [String]
    let isDefaultOn: Bool
    let displayName: String
}

enum SupportedTypes {
    // Keep in sync with CFBundleDocumentTypes / UTImportedTypeDeclarations in Info.plist (checked by tests).
    static let all: [SupportedType] = [
        .init(identifier: "public.zip-archive", extensions: ["zip"], isDefaultOn: true, displayName: "ZIP"),
        .init(identifier: "com.winzip.zipx-archive", extensions: ["zipx"], isDefaultOn: true, displayName: "ZIPX"),
        .init(identifier: "org.7-zip.7-zip-archive", extensions: ["7z"], isDefaultOn: true, displayName: "7z"),
        .init(identifier: "com.rarlab.rar-archive", extensions: ["rar"], isDefaultOn: true, displayName: "RAR"),
        .init(identifier: "public.tar-archive", extensions: ["tar"], isDefaultOn: true, displayName: "TAR"),
        .init(identifier: "org.gnu.gnu-zip-archive", extensions: ["gz", "gzip"], isDefaultOn: true, displayName: "GZIP"),
        .init(identifier: "org.gnu.gnu-zip-tar-archive", extensions: ["tgz"], isDefaultOn: true, displayName: "TGZ"),
        .init(identifier: "public.bzip2-archive", extensions: ["bz2", "bzip2"], isDefaultOn: true, displayName: "BZIP2"),
        .init(identifier: "public.tar-bzip2-archive", extensions: ["tbz", "tbz2"], isDefaultOn: true, displayName: "TBZ"),
        .init(identifier: "org.tukaani.xz-archive", extensions: ["xz"], isDefaultOn: true, displayName: "XZ"),
        .init(identifier: "org.tukaani.tar-xz-archive", extensions: ["txz"], isDefaultOn: true, displayName: "TXZ"),
        .init(identifier: "com.facebook.zstandard-archive", extensions: ["zst"], isDefaultOn: true, displayName: "Zstandard"),
        .init(identifier: "public.lz4-archive", extensions: ["lz4"], isDefaultOn: true, displayName: "LZ4"),
        .init(identifier: "public.z-archive", extensions: ["z"], isDefaultOn: true, displayName: "Z"),
        .init(identifier: "com.microsoft.cab", extensions: ["cab"], isDefaultOn: true, displayName: "CAB"),
        .init(identifier: "io.github.mrgamingita.zzzip.arj", extensions: ["arj"], isDefaultOn: true, displayName: "ARJ"),
        .init(identifier: "public.archive.lha", extensions: ["lzh", "lha"], isDefaultOn: true, displayName: "LZH"),
        .init(identifier: "public.cpio-archive", extensions: ["cpio"], isDefaultOn: true, displayName: "CPIO"),
        .init(identifier: "com.microsoft.wim-archive", extensions: ["wim"], isDefaultOn: true, displayName: "WIM"),
        .init(identifier: "io.github.mrgamingita.zzzip.split-001", extensions: ["001"], isDefaultOn: true, displayName: "Split (.001)"),
        .init(identifier: "io.github.mrgamingita.zzzip.rar-volume", extensions: ["r00"], isDefaultOn: true, displayName: "RAR volume (.r00)"),
        .init(identifier: "io.github.mrgamingita.zzzip.zip-volume", extensions: ["z01"], isDefaultOn: true, displayName: "ZIP volume (.z01)"),
        .init(identifier: "public.iso-image", extensions: ["iso"], isDefaultOn: false, displayName: "ISO"),
        .init(identifier: "com.apple.disk-image-udif", extensions: ["dmg"], isDefaultOn: false, displayName: "DMG"),
        .init(identifier: "com.apple.installer-package-archive", extensions: ["pkg"], isDefaultOn: false, displayName: "PKG"),
        .init(identifier: "com.apple.xar-archive", extensions: ["xar"], isDefaultOn: false, displayName: "XAR"),
    ]

    static let allExtensions: Set<String> = Set(all.flatMap(\.extensions))

    /// Zip-based formats people open as archives on purpose (not associated by default).
    static let zipBasedExtensions: Set<String> = ["jar", "apk", "epub", "xpi", "ipa", "appx", "ova", "swm", "esd", "vhd", "vmdk"]

    static func isArchive(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if allExtensions.contains(ext) || zipBasedExtensions.contains(ext) { return true }
        return url.lastPathComponent.range(of: #"\.\d{3}$"#, options: .regularExpression) != nil
    }
}
