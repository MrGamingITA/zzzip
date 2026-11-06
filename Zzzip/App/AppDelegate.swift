import AppKit

/// Routes non-archives (from the Open panel too) to archive creation.
final class ZzzipDocumentController: NSDocumentController {
    override func openDocument(withContentsOf url: URL, display: Bool, completionHandler: @escaping (NSDocument?, Bool, Error?) -> Void) {
        if SupportedTypes.isArchive(url) {
            super.openDocument(withContentsOf: url, display: display, completionHandler: completionHandler)
        } else {
            CreateArchiveController.show(sources: [url])
            completionHandler(nil, false, nil)
        }
    }

    override func typeForContents(of url: URL) throws -> String { "Archive" }
    override func documentClass(forType typeName: String) -> AnyClass? { ArchiveDocument.self }

    /// File ▸ Open…: everything chosen at once goes through the same routing as a Dock drop
    /// (archives open, other files become one new archive).
    override func openDocument(_ sender: Any?) {
        let p = NSOpenPanel()
        p.canChooseFiles = true; p.canChooseDirectories = true; p.allowsMultipleSelection = true
        p.prompt = String(localized: "Open")
        if p.runModal() == .OK { AppDelegate.route(p.urls) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let service = FinderService()

    func applicationWillFinishLaunching(_ notification: Notification) {
        _ = ZzzipDocumentController()   // the first instance becomes NSDocumentController.shared
        CacheManager.shared.purgeAll()   // before any launch-time open creates a session
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.applicationIconImage = AppIcon.image
        NSApp.servicesProvider = service
        NSUpdateDynamicServices()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if NSDocumentController.shared.documents.isEmpty && CreateArchiveController.open.isEmpty { WelcomeWindowController.shared.present() }
        }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { WelcomeWindowController.shared.present() }
        return true
    }

    /// Finder double-click / drop on the Dock icon / "Open With".
    func application(_ application: NSApplication, open urls: [URL]) { Self.route(urls) }

    static func route(_ urls: [URL]) {
        let archives = urls.filter(SupportedTypes.isArchive)
        let others = urls.filter { !SupportedTypes.isArchive($0) }
        for a in archives {
            NSDocumentController.shared.openDocument(withContentsOf: a, display: true) { _, _, err in
                if let err { NSAlert(error: err).runModal() }
            }
        }
        if !others.isEmpty { CreateArchiveController.show(sources: others) }
        if !urls.isEmpty { WelcomeWindowController.shared.close() }
    }

    static func makeDefaultInteractively() {
        let types = SupportedTypes.all.filter(\.isDefaultOn)
        Task { @MainActor in
            do {
                try await DefaultAppManager.shared.setZzzipDefault(for: types)
                WelcomeWindowController.shared.refresh()
            } catch { NSAlert(error: error).runModal() }
        }
    }

    @objc func showAbout(_ sender: Any?) {
        var opts: [NSApplication.AboutPanelOptionKey: Any] = [:]
        if let u = Bundle.main.url(forResource: "License", withExtension: "txt"), let t = try? String(contentsOf: u, encoding: .utf8) {
            let head = String(localized: "Zzzip uses 7-Zip 26.05 by Igor Pavlov (GNU LGPL, with the unRAR restriction).") + "\n\n"
            opts[.credits] = NSAttributedString(string: head + t, attributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.labelColor])
        }
        NSApp.orderFrontStandardAboutPanel(options: opts)
    }
    @objc func showSettings(_ sender: Any?) { SettingsWindowController.shared.present() }
    @objc func newArchive(_ sender: Any?) { CreateArchiveController.chooseAndShow() }
}
