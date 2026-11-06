import AppKit

extension ArchiveWindowController {
    /// Archives with encrypted entries: get the password before writing, so new files are encrypted too.
    func ensurePasswordForWriting() async throws {
        guard let info = doc.info, FormatCapabilities.needsPasswordBeforeWriting(info: info, password: doc.password) else { return }
        guard let pw = await askPassword(wrong: false), !pw.isEmpty else { throw EngineError.cancelled }
        // Check it against the archive before using it.
        try await SevenZip.bundled.test(doc.workingURL, password: pw)
        doc.password = pw
    }

    @objc func addFiles(_ sender: Any?) {
        guard let w = window, doc.isWritable else { return }
        let p = NSOpenPanel()
        p.canChooseFiles = true; p.canChooseDirectories = true; p.allowsMultipleSelection = true
        p.prompt = String(localized: "Add")
        p.beginSheetModal(for: w) { r in if r == .OK { self.confirmAndAdd(p.urls) } }
    }

    func fileListDropFiles(_ urls: [URL]) -> Bool {
        guard doc.isWritable, !urls.isEmpty else { return false }
        DispatchQueue.main.async { self.confirmAndAdd(urls) }
        return true
    }

    func confirmAndAdd(_ urls: [URL]) {
        guard let w = window else { return }
        let folder = currentFolder?.isRoot == false ? currentFolder!.path : ""
        let a = NSAlert()
        let into = folder.isEmpty ? doc.archiveURL.lastPathComponent : folder
        a.messageText = urls.count == 1 ? String(localized: "Add “\(urls[0].lastPathComponent)” to “\(into)”?") : String(localized: "Add \(urls.count) items to “\(into)”?")
        a.informativeText = urls.map(\.lastPathComponent).prefix(8).joined(separator: ", ")
        a.addButton(withTitle: String(localized: "Add"))
        a.addButton(withTitle: String(localized: "Cancel"))
        a.beginSheetModal(for: w) { r in
            guard r == .alertFirstButtonReturn, !self.busy else { return }
            Task { @MainActor in
                do {
                    try await self.ensurePasswordForWriting()
                    try await self.withPassword { pw in
                        try await self.runWithProgress(title: String(localized: "Adding to “\(self.doc.archiveURL.lastPathComponent)”…")) { progress, cancel in
                            try await ArchiveEditor(engine: .bundled).add(files: urls, intoFolder: folder, archive: self.doc.workingURL, password: pw,
                                                                          encryptHeaders: self.doc.needsHeaderPassword, progress: progress, cancel: cancel)
                        }
                    }
                    self.reload(keepingFolder: folder)
                } catch { await self.showError(error) }
            }
        }
    }

    @objc func deleteSelection(_ sender: Any?) {
        let nodes = fileList.selectedNodes
        guard let w = window, doc.isWritable, !nodes.isEmpty else { return }
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = nodes.count == 1 ? String(localized: "Delete “\(nodes[0].name)” from the archive? This can't be undone.") : String(localized: "Delete \(nodes.count) items from the archive? This can't be undone.")
        a.informativeText = nodes.map(\.name).prefix(8).joined(separator: ", ")
        a.addButton(withTitle: String(localized: "Delete"))
        a.addButton(withTitle: String(localized: "Cancel"))
        a.buttons.first?.hasDestructiveAction = true
        let folder = currentFolder?.path
        a.beginSheetModal(for: w) { r in
            guard r == .alertFirstButtonReturn, !self.busy else { return }
            Task { @MainActor in
                do {
                    try await self.withPassword { pw in
                        try await self.runWithProgress(title: String(localized: "Deleting from “\(self.doc.archiveURL.lastPathComponent)”…")) { _, cancel in
                            try await ArchiveEditor(engine: .bundled).delete(paths: nodes.map(\.archivePath), archive: self.doc.workingURL, password: pw, cancel: cancel)
                        }
                    }
                    self.reload(keepingFolder: folder)
                } catch { await self.showError(error) }
            }
        }
    }
}
