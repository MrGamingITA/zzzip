import AppKit
import SwiftUI

/// The "New Archive" window: options, then creation with progress, then a result prompt.
final class CreateArchiveController: NSWindowController, NSWindowDelegate {
    static var open: [CreateArchiveController] = []
    let model: CreateArchiveModel

    static func show(sources: [URL]) {
        guard !sources.isEmpty else { return }
        let c = CreateArchiveController(sources: sources)
        open.append(c)
        c.showWindow(nil)
        c.window?.center()
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Asks for files first (⌘N / welcome button).
    static func chooseAndShow() {
        let p = NSOpenPanel()
        p.canChooseFiles = true; p.canChooseDirectories = true; p.allowsMultipleSelection = true
        p.prompt = String(localized: "Choose")
        p.message = String(localized: "Choose the files and folders to compress")
        if p.runModal() == .OK { show(sources: p.urls) }
    }

    init(sources: [URL]) {
        model = CreateArchiveModel(sources: sources)
        let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = String(localized: "New Archive")
        w.isRestorable = false
        super.init(window: w)
        w.delegate = self
        let view = CreateArchiveView(model: model, favorites: Favorites().items,
                                     onCancel: { [weak self] in self?.close() },
                                     onCreate: { [weak self] o in self?.create(o) })
        w.contentViewController = NSHostingController(rootView: view)
    }
    required init?(coder: NSCoder) { fatalError() }

    func windowWillClose(_ notification: Notification) { Self.open.removeAll { $0 === self } }

    private func create(_ options: CreateOptions) {
        guard let w = window else { return }
        Settings.lastCreateOptions = options
        let sources = model.sources
        let sheet = ProgressSheet(title: String(localized: "Creating “\(options.name).\(options.format.fileExtension)”…"))
        w.beginSheet(sheet.window!, completionHandler: nil)
        Task { @MainActor in
            do {
                if options.trashOriginals {
                    let a = NSAlert()
                    a.messageText = String(localized: "Move the originals to the Trash after creating the archive?")
                    a.addButton(withTitle: String(localized: "Move to Trash")); a.addButton(withTitle: String(localized: "Keep Originals"))
                    w.endSheet(sheet.window!)
                    let r = await a.beginSheetModal(for: w)
                    var o = options; o.trashOriginals = r == .alertFirstButtonReturn
                    w.beginSheet(sheet.window!, completionHandler: nil)
                    try await self.run(o, sources: sources, sheet: sheet)
                } else {
                    try await self.run(options, sources: sources, sheet: sheet)
                }
            } catch {
                w.endSheet(sheet.window!)
                if (error as? EngineError) != .cancelled {
                    let a = NSAlert(); a.alertStyle = .warning
                    a.messageText = String(localized: "Zzzip couldn't complete the operation.")
                    a.informativeText = (error as? EngineError)?.userMessage ?? error.localizedDescription
                    await a.beginSheetModal(for: w)
                }
            }
        }
    }

    @MainActor private func run(_ o: CreateOptions, sources: [URL], sheet: ProgressSheet) async throws {
        let url = try await ArchiveCreator(engine: .bundled).create(sources: sources, options: o,
                                                                    progress: { v in DispatchQueue.main.async { sheet.update(v) } }, cancel: sheet.token)
        window?.endSheet(sheet.window!)
        close()
        let a = NSAlert()
        a.messageText = String(localized: "Archive created")
        a.informativeText = url.lastPathComponent
        a.addButton(withTitle: String(localized: "Show in Finder"))
        a.addButton(withTitle: String(localized: "Open in Zzzip"))
        a.addButton(withTitle: String(localized: "OK"))
        switch a.runModal() {
        case .alertFirstButtonReturn: NSWorkspace.shared.activateFileViewerSelecting([url])
        case .alertSecondButtonReturn: NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
        default: break
        }
    }
}
