import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct WelcomeView: View {
    let recents: [URL]
    let showDefaultButton: Bool
    let openArchive: (URL) -> Void
    let handleDrop: ([URL]) -> Void
    let newArchive: () -> Void
    let openPanel: () -> Void
    let makeDefault: () -> Void
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: AppIcon.image).resizable().frame(width: 96, height: 96)
            Text("Zzzip").font(.largeTitle.bold())
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [7]))
                .foregroundStyle(targeted ? Color.accentColor : Color.secondary.opacity(0.5))
                .background(RoundedRectangle(cornerRadius: 14).fill(targeted ? Color.accentColor.opacity(0.08) : .clear))
                .frame(height: 110)
                .overlay(VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down").font(.system(size: 28))
                    Text(String(localized: "Drop an archive here to open it")).font(.headline)
                    Text(String(localized: "or other files to compress them")).foregroundStyle(.secondary)
                })
                .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
                    let group = DispatchGroup(); var urls: [URL] = []
                    for p in providers {
                        group.enter()
                        _ = p.loadObject(ofClass: URL.self) { u, _ in if let u { DispatchQueue.main.async { urls.append(u) } }; group.leave() }
                    }
                    group.notify(queue: .main) { handleDrop(urls) }
                    return true
                }
            HStack {
                Button(String(localized: "Open Archive…"), action: openPanel)
                Button(String(localized: "New Archive…"), action: newArchive)
            }
            if !recents.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Recent")).font(.caption).foregroundStyle(.secondary)
                    ForEach(recents.prefix(6), id: \.path) { u in
                        Button { openArchive(u) } label: {
                            HStack {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: u.path)).resizable().frame(width: 16, height: 16)
                                Text(u.lastPathComponent).lineLimit(1).truncationMode(.middle)
                                Spacer()
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if showDefaultButton {
                Button(String(localized: "Make Zzzip the default app for archives"), action: makeDefault).buttonStyle(.link)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

final class WelcomeWindowController: NSWindowController {
    static let shared = WelcomeWindowController()

    init() {
        let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true; w.titleVisibility = .hidden; w.isRestorable = false
        w.isMovableByWindowBackground = true
        super.init(window: w)
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }

    func refresh() {
        let view = WelcomeView(
            recents: NSDocumentController.shared.recentDocumentURLs.filter { FileManager.default.fileExists(atPath: $0.path) },
            showDefaultButton: !DefaultAppManager.shared.isDefaultForZip,
            openArchive: { u in NSDocumentController.shared.openDocument(withContentsOf: u, display: true) { _, _, _ in } },
            handleDrop: { urls in AppDelegate.route(urls) },
            newArchive: { CreateArchiveController.chooseAndShow() },
            openPanel: { NSDocumentController.shared.openDocument(nil) },
            makeDefault: { AppDelegate.makeDefaultInteractively() })
        window?.contentViewController = NSHostingController(rootView: view)
    }

    func present() { refresh(); showWindow(nil); window?.center(); NSApp.activate(ignoringOtherApps: true) }
}
