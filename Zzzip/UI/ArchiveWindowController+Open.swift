import AppKit
import Quartz
import UniformTypeIdentifiers

private var previewURLsKey = 0

extension ArchiveWindowController {
    /// Extracts nodes into a fresh folder of this window's cache session (files only), returning their URLs.
    func extractToCache(_ nodes: [ArchiveNode]) async throws -> [URL] {
        let dir = session.appendingPathComponent(UUID().uuidString, isDirectory: true)
        return try await withPassword { pw in
            try await self.runWithProgress(title: String(localized: "Preparing “\(nodes.first?.name ?? "")”…")) { progress, cancel in
                try await Extractor(engine: .bundled).extract(archive: self.doc.workingURL, items: nodes, destination: dir, mode: .loose, password: pw,
                                                              onConflict: { _ in ConflictAnswer(decision: .replace, applyToAll: true) },
                                                              progress: progress, cancel: cancel)
            }
        }
    }

    func openNodes(_ nodes: [ArchiveNode], with app: URL? = nil) {
        let files = nodes.filter { !$0.isFolder }
        if files.isEmpty, let f = nodes.first(where: \.isFolder) { navigate(to: f); return }
        Task { @MainActor in
            do {
                let urls = try await extractToCache(files)
                for (u, n) in zip(urls, files) where doc.isWritable { watcher.track(file: u, internalPath: n.archivePath) }
                if let app {
                    try await NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
                } else {
                    urls.forEach { NSWorkspace.shared.open($0) }
                }
            } catch { await showError(error) }
        }
    }

    @objc func openSelection(_ sender: Any?) { openNodes(fileList.selectedNodes) }

    @objc func openWith(_ sender: Any?) {
        guard let w = window else { return }
        let nodes = fileList.selectedNodes.filter { !$0.isFolder }
        let p = NSOpenPanel()
        p.directoryURL = URL(fileURLWithPath: "/Applications")
        p.allowedContentTypes = [.application]
        p.prompt = String(localized: "Open")
        p.message = String(localized: "Choose an app to open the selected files")
        p.beginSheetModal(for: w) { r in if r == .OK, let app = p.url { self.openNodes(nodes, with: app) } }
    }

    @objc func copyPath(_ sender: Any?) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(fileList.selectedNodes.map(\.path).joined(separator: "\n"), forType: .string)
    }

    // MARK: modified files (opened from the archive and edited)

    func checkModifiedFiles(thenClose: Bool = false) {
        let changed = watcher.modifiedFiles()
        guard !changed.isEmpty, !busy, let w = window, w.attachedSheet == nil else { if thenClose && changed.isEmpty { closeNow() }; return }
        Task { @MainActor in
            var updated = false
            for c in changed {
                let a = NSAlert()
                a.messageText = String(localized: "“\(c.file.lastPathComponent)” was modified. Update it in the archive?")
                a.informativeText = c.internalPath
                a.addButton(withTitle: String(localized: "Update"))
                a.addButton(withTitle: String(localized: "Don't Update"))
                let r = await a.beginSheetModal(for: w)
                watcher.markSynced(c.file)
                guard r == .alertFirstButtonReturn else { continue }
                do {
                    try await ensurePasswordForWriting()
                    try await withPassword { pw in
                        try await self.runWithProgress(title: String(localized: "Updating “\(self.doc.archiveURL.lastPathComponent)”…")) { _, _ in
                            try await ArchiveEditor(engine: .bundled).update(file: c.file, internalPath: c.internalPath, archive: self.doc.workingURL,
                                                                             password: pw, encryptHeaders: self.doc.needsHeaderPassword)
                        }
                    }
                    updated = true
                } catch { await showError(error) }
            }
            if thenClose { closeNow() } else if updated { reload(keepingFolder: currentFolder?.path) }
        }
    }

    private func closeNow() { closingConfirmed = true; window?.performClose(nil) }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if closingConfirmed || watcher.modifiedFiles().isEmpty { return true }
        checkModifiedFiles(thenClose: true)
        return false
    }

    // MARK: context menu

    func contextMenu() -> NSMenu? {
        guard !fileList.selectedNodes.isEmpty else { return nil }
        let m = NSMenu()
        func add(_ t: String, _ s: Selector) { m.addItem(withTitle: t, action: s, keyEquivalent: "").target = self }
        add(String(localized: "Open"), #selector(openSelection(_:)))
        add(String(localized: "Open With…"), #selector(openWith(_:)))
        add(String(localized: "Preview"), #selector(previewSelection(_:)))
        m.addItem(.separator())
        add(String(localized: "Extract To…"), #selector(extractTo(_:)))
        add(String(localized: "Extract Here"), #selector(extractHere(_:)))
        m.addItem(.separator())
        add(String(localized: "Copy Path"), #selector(copyPath(_:)))
        if fileList.isSearching { add(String(localized: "Show in Enclosing Folder"), #selector(revealInFolder(_:))) }
        m.addItem(.separator())
        add(String(localized: "Delete"), #selector(deleteSelection(_:)))
        return m
    }

    @objc func revealInFolder(_ sender: Any?) {
        guard let n = fileList.selectedNodes.first, let p = n.parent else { return }
        navigate(to: p); fileList.select(path: n.path)
    }

    // MARK: drag out (file promises)

    func fileListPromiseProvider(for node: ArchiveNode) -> NSPasteboardWriting? {
        let type = node.isFolder ? UTType.folder.identifier : (Fmt.utType(for: node) ?? .data).identifier
        let p = NSFilePromiseProvider(fileType: type, delegate: self)
        p.userInfo = node.path
        return p
    }

    func fileListGoUp() { goUp(nil) }
}

extension ArchiveWindowController: NSFilePromiseProviderDelegate {
    func filePromiseProvider(_ p: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        (p.userInfo as? String).flatMap { doc.root?.node(atPath: $0)?.name } ?? "file"
    }

    func operationQueue(for p: NSFilePromiseProvider) -> OperationQueue { promiseQueue }

    func filePromiseProvider(_ p: NSFilePromiseProvider, writePromiseTo url: URL, completionHandler: @escaping (Error?) -> Void) {
        let path = p.userInfo as? String ?? ""
        DispatchQueue.main.async {
            guard let node = self.doc.root?.node(atPath: path) else { completionHandler(CocoaError(.fileNoSuchFile)); return }
            Task { @MainActor in
                do {
                    _ = try await self.dragRunner.run { @MainActor in try await self.withPassword { pw in
                        try await self.runWithProgress(title: String(localized: "Extracting “\(node.name)”…")) { progress, cancel in
                            try await Extractor(engine: .bundled).extract(archive: self.doc.workingURL, items: [node], destination: url.deletingLastPathComponent(),
                                                                          mode: .loose, password: pw, onConflict: { u in await self.askConflict(for: u) },
                                                                          progress: progress, cancel: cancel)
                        }
                    } }
                    completionHandler(nil)
                } catch {
                    completionHandler(error)
                    await self.showError(error)
                }
            }
        }
    }
}

// MARK: Quick Look

extension ArchiveWindowController: QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    var previewURLs: [URL] {
        get { objc_getAssociatedObject(self, &previewURLsKey) as? [URL] ?? [] }
        set { objc_setAssociatedObject(self, &previewURLsKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    @objc func previewSelection(_ sender: Any?) {
        guard let panel = QLPreviewPanel.shared() else { return }
        if QLPreviewPanel.sharedPreviewPanelExists() && panel.isVisible { panel.orderOut(nil); return }
        loadPreview { panel.makeKeyAndOrderFront(nil) }
    }

    func refreshQuickLook() {
        guard QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared(), panel.isVisible else { return }
        loadPreview { panel.reloadData() }
    }

    private func loadPreview(_ then: @escaping () -> Void) {
        let files = fileList.selectedNodes.filter { !$0.isFolder }
        guard !files.isEmpty else { return }
        previewGeneration += 1
        let generation = previewGeneration
        Task { @MainActor in
            do {
                let urls = try await extractToCache(files)
                guard generation == self.previewGeneration else { return }   // selection changed meanwhile
                previewURLs = urls; then()
            } catch { await showError(error) }
        }
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) { panel.dataSource = self; panel.delegate = self }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) { panel.dataSource = nil; panel.delegate = nil }
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { previewURLs.count }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! { previewURLs[index] as NSURL }
    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        if event.type == .keyDown { fileList.table.keyDown(with: event); return true }
        return false
    }
}
