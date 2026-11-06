import AppKit

/// One open archive. Read-only from NSDocument's point of view: Zzzip never "saves" a document.
final class ArchiveDocument: NSDocument {
    var info: ArchiveInfo?
    var root: ArchiveNode?
    var password: String?
    var needsHeaderPassword = false
    var isWritable: Bool { innerTar == nil && (info.map { FormatCapabilities.isWritable(info: $0, url: archiveURL) } ?? false) }
    var archiveURL: URL { fileURL ?? URL(fileURLWithPath: "/") }
    /// Decompressed inner tar for .tar.gz & co; nil for every other archive.
    private(set) var innerTar: URL?
    private(set) var outerType: String?
    /// The file every 7zz operation runs on.
    var workingURL: URL { innerTar ?? archiveURL }
    /// Format shown to the user (e.g. "TAR.GZ").
    var displayType: String { outerType.map { "TAR.\($0 == "gzip" ? "GZ" : $0 == "bzip2" ? "BZ2" : $0.uppercased())" } ?? (info?.type.uppercased() ?? "") }
    private lazy var cacheSession: URL = CacheManager.shared.makeSession()

    override func close() {
        CacheManager.shared.remove(session: cacheSession)
        super.close()
    }

    override class var autosavesInPlace: Bool { false }
    override func read(from url: URL, ofType typeName: String) throws {}
    override func data(ofType typeName: String) throws -> Data { throw CocoaError(.featureUnsupported) }
    override var isDocumentEdited: Bool { false }

    override func makeWindowControllers() {
        let wc = ArchiveWindowController(document: self)
        addWindowController(wc)
        wc.reload()
    }

    /// Lists the archive again (after edits). Throws EngineError.
    func load(cancel: CancelToken? = nil) async throws {
        var info = try await SevenZip.bundled.list(workingURL, password: password)
        if innerTar == nil, let inner = try await InnerTar.resolve(archive: archiveURL, info: info, engine: .bundled, cacheDir: cacheSession, cancel: cancel) {
            outerType = info.type.lowercased()
            innerTar = inner
            info = try await SevenZip.bundled.list(inner, password: password)
        }
        self.info = info
        self.root = ArchiveTree.build(info.entries)
    }
}
