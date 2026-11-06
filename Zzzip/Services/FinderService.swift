import AppKit

/// Finder ▸ Services / Quick Actions ▸ "Compress with Zzzip".
final class FinderService: NSObject {
    @objc func compressWithZzzip(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = (pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        guard !urls.isEmpty else { error.pointee = String(localized: "No files to compress.") as NSString; return }
        DispatchQueue.main.async { CreateArchiveController.show(sources: urls) }
    }
}
