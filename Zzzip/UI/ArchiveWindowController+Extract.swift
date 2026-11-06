import AppKit
import SwiftUI

extension ArchiveWindowController {
    // MARK: generic helpers

    /// Runs `op` showing the progress sheet only if it takes longer than 0.5 s.
    func runWithProgress<T>(title: String, _ op: @escaping (_ progress: @escaping (Double) -> Void, _ cancel: CancelToken) async throws -> T) async throws -> T {
        let sheet = ProgressSheet(title: title)
        busyCounter.begin(); busy = busyCounter.isBusy
        var shown = false
        let showTask = Task { @MainActor in
            try await Task.sleep(nanoseconds: 500_000_000)
            // Never cover a question (conflict/password) that is already on screen.
            guard let w = self.window, let sw = sheet.window, w.attachedSheet == nil else { return }
            shown = true
            w.beginSheet(sw, completionHandler: nil)
        }
        defer {
            showTask.cancel()
            if shown, let sw = sheet.window { sw.sheetParent?.endSheet(sw); sw.orderOut(nil) }
            busyCounter.end(); busy = busyCounter.isBusy
        }
        return try await op({ v in DispatchQueue.main.async { sheet.update(v) } }, sheet.token)
    }

    /// Runs an engine operation, asking for the password again while it is missing or wrong.
    func withPassword<T>(_ op: @escaping (String?) async throws -> T) async throws -> T {
        while true {
            do { return try await op(doc.password) }
            catch let e as EngineError where e == .passwordRequired || e == .wrongPassword {
                guard let pw = await askPassword(wrong: e == .wrongPassword) else { throw EngineError.cancelled }
                doc.password = pw
            }
        }
    }

    func askPassword(wrong: Bool) async -> String? {
        guard let w = window else { return nil }
        let a = NSAlert()
        a.messageText = wrong ? String(localized: "The password is wrong.") : String(localized: "This archive is protected by a password.")
        a.informativeText = String(localized: "Enter the password for “\(doc.archiveURL.lastPathComponent)”.")
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        a.accessoryView = field
        a.addButton(withTitle: String(localized: "OK"))
        a.addButton(withTitle: String(localized: "Cancel"))
        a.window.initialFirstResponder = field
        if !w.isVisible { w.makeKeyAndOrderFront(nil) }
        let r = await a.beginSheetModal(for: SheetHost.clear(w))
        return r == .alertFirstButtonReturn ? field.stringValue : nil
    }

    func askConflict(for url: URL) async -> ConflictAnswer {
        switch Settings.conflictPolicy {
        case .replace: return ConflictAnswer(decision: .replace, applyToAll: true)
        case .skip: return ConflictAnswer(decision: .skip, applyToAll: true)
        case .ask: break
        }
        guard let w = window else { return ConflictAnswer(decision: .skip, applyToAll: false) }
        let a = NSAlert()
        a.messageText = String(localized: "“\(url.lastPathComponent)” already exists in this location.")
        a.informativeText = String(localized: "Do you want to replace it, skip it or keep both?")
        a.addButton(withTitle: String(localized: "Replace"))
        a.addButton(withTitle: String(localized: "Skip"))
        a.addButton(withTitle: String(localized: "Keep Both"))
        a.showsSuppressionButton = true
        a.suppressionButton?.title = String(localized: "Apply to all")
        let r = await a.beginSheetModal(for: SheetHost.clear(w))
        let all = a.suppressionButton?.state == .on
        switch r {
        case .alertFirstButtonReturn: return ConflictAnswer(decision: .replace, applyToAll: all)
        case .alertThirdButtonReturn: return ConflictAnswer(decision: .keepBoth, applyToAll: all)
        default: return ConflictAnswer(decision: .skip, applyToAll: all)
        }
    }

    func showError(_ error: Error) async {
        if (error as? EngineError) == .cancelled { return }
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = String(localized: "Zzzip couldn't complete the operation.")
        a.informativeText = (error as? EngineError)?.userMessage ?? error.localizedDescription
        if let w = window, w.isVisible { await a.beginSheetModal(for: SheetHost.host(for: w)) } else { a.runModal() }
    }

    func showBanner(_ message: String, buttons: [(String, () -> Void)]) {
        bannerHost.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let b = BannerView(message: message, buttons: buttons)
        bannerHost.addArrangedSubview(b)
        b.widthAnchor.constraint(equalTo: bannerHost.widthAnchor).isActive = true
    }

    func nodes(forPaths paths: [String]) -> [ArchiveNode] { paths.compactMap { doc.root?.node(atPath: $0) } }

    // MARK: extraction

    func extract(_ items: [ArchiveNode], to destination: URL, mode: ExtractionMode = .smart) {
        Task { @MainActor in
            do {
                let created = try await withPassword { pw in
                    try await self.runWithProgress(title: String(localized: "Extracting “\(self.doc.archiveURL.lastPathComponent)”…")) { progress, cancel in
                        try await Extractor(engine: .bundled).extract(archive: self.doc.workingURL, items: items, destination: destination, mode: mode,
                                                                      password: pw, namedAfter: self.doc.archiveURL, onConflict: { url in await self.askConflict(for: url) },
                                                                      progress: progress, cancel: cancel)
                    }
                }
                guard !created.isEmpty else { return }
                if Settings.openFinderAfterExtract {
                    NSWorkspace.shared.activateFileViewerSelecting(created)
                } else {
                    let place = FileManager.default.displayName(atPath: (created.count == 1 ? created[0].deletingLastPathComponent() : destination).path)
                    let what = created.count == 1 ? created[0].lastPathComponent : place
                    showBanner(String(localized: "Extracted “\(what)” to \(place)"),
                               buttons: [(String(localized: "Show in Finder"), { NSWorkspace.shared.activateFileViewerSelecting(created) })])
                }
            } catch {
                await showError(error)
            }
        }
    }

    /// Selection, or nothing (= whole archive) when nothing is selected. Inside a subfolder with no selection: that folder's contents.
    var extractionItems: [ArchiveNode] {
        let sel = fileList.selectedNodes
        if !sel.isEmpty { return sel }
        if let f = currentFolder, !f.isRoot, !fileList.isSearching { return f.children }
        return []
    }

    @objc func extractTo(_ sender: Any?) {
        guard let w = window else { return }
        let items = extractionItems
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
        p.prompt = String(localized: "Extract")
        p.message = String(localized: "Choose where to extract")
        p.directoryURL = doc.archiveURL.deletingLastPathComponent()
        p.beginSheetModal(for: w) { r in
            guard r == .OK, let u = p.url else { return }
            self.extract(items, to: u)
        }
    }

    @objc func extractHere(_ sender: Any?) {
        extract(extractionItems, to: doc.archiveURL.deletingLastPathComponent())
    }

    func extractToDestination(_ item: DestinationItem, confirm: Bool, paths: [String]?) {
        guard let dest = item.url(archive: doc.archiveURL) else { return }
        let items = paths.map(nodes(forPaths:)) ?? extractionItems
        guard confirm, let w = window else { extract(items, to: dest); return }
        let a = NSAlert()
        let count = items.isEmpty ? (doc.root?.children.count ?? 0) : items.count
        a.messageText = items.isEmpty ? String(localized: "Extract the whole archive to “\(item.title)”?")
                                      : (count == 1 ? String(localized: "Extract “\(items[0].name)” to “\(item.title)”?") : String(localized: "Extract \(count) items to “\(item.title)”?"))
        a.informativeText = dest.path
        a.addButton(withTitle: String(localized: "Extract"))
        a.addButton(withTitle: String(localized: "Cancel"))
        a.beginSheetModal(for: w) { r in if r == .alertFirstButtonReturn { self.extract(items, to: dest) } }
    }

    // MARK: test & info

    @objc func testArchive(_ sender: Any?) {
        Task { @MainActor in
            do {
                try await withPassword { pw in
                    try await self.runWithProgress(title: String(localized: "Testing “\(self.doc.archiveURL.lastPathComponent)”…")) { progress, cancel in
                        try await SevenZip.bundled.test(self.doc.workingURL, password: pw, progress: progress, cancel: cancel)
                    }
                }
                let a = NSAlert()
                a.messageText = String(localized: "No errors found")
                a.informativeText = String(localized: "“\(doc.archiveURL.lastPathComponent)” is intact.")
                if let w = window { await a.beginSheetModal(for: w) }
            } catch { await showError(error) }
        }
    }

    @objc func showInfo(_ sender: Any?) {
        guard let info = doc.info, let root = doc.root, let w = window else { return }
        var hosting: NSHostingController<InfoView>!
        hosting = NSHostingController(rootView: InfoView(url: doc.archiveURL, info: info, root: root,
                                                         encrypted: info.hasEncryptedEntries || doc.needsHeaderPassword, typeLabel: doc.displayType,
                                                         close: { [weak w] in if let s = hosting.view.window { w?.endSheet(s) } }))
        let sheet = NSWindow(contentViewController: hosting)
        w.beginSheet(sheet, completionHandler: nil)
    }
}
