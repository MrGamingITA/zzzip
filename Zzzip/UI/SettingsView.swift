import SwiftUI
import AppKit

final class SettingsModel: ObservableObject {
    @Published var format = Settings.defaultFormat { didSet { Settings.defaultFormat = format } }
    @Published var level = Settings.defaultLevel { didSet { Settings.defaultLevel = level } }
    @Published var policy = Settings.conflictPolicy { didSet { Settings.conflictPolicy = policy } }
    @Published var openFinder = Settings.openFinderAfterExtract { didSet { Settings.openFinderAfterExtract = openFinder } }
    @Published var favorites: [URL] = Favorites().items
    @Published var selectedTypes: Set<String> = []
    @Published var status = ""

    init() {
        let current = SupportedTypes.all.filter(DefaultAppManager.shared.isZzzipDefault).map(\.identifier)
        selectedTypes = Set(SupportedTypes.all.filter(\.isDefaultOn).map(\.identifier)).union(current)
    }
    var chosen: [SupportedType] { SupportedTypes.all.filter { selectedTypes.contains($0.identifier) } }
}

struct UpdatesSettingsView: View {
    @ObservedObject var u = AppUpdater.shared
    @State private var lastCheck = AppUpdater.shared.lastCheck

    private var version: String {
        let i = Bundle.main.infoDictionary ?? [:]
        return "\(i["CFBundleShortVersionString"] as? String ?? "?") (\(i["CFBundleVersion"] as? String ?? "?"))"
    }

    var body: some View {
        Form {
            Toggle(String(localized: "Check for updates automatically"), isOn: Binding(get: { u.automaticallyChecks }, set: { u.automaticallyChecks = $0 }))
            Picker(String(localized: "Check:"), selection: Binding(get: { u.interval }, set: { u.interval = $0 })) {
                ForEach(UpdateInterval.allCases, id: \.self) { Text($0.title).tag($0) }
            }.disabled(!u.automaticallyChecks)
            Toggle(String(localized: "Download and install updates automatically"), isOn: Binding(get: { u.automaticallyDownloads }, set: { u.automaticallyDownloads = $0 }))
                .disabled(!u.automaticallyChecks)
            Text(String(localized: "Updates come from the Zzzip releases on GitHub and are verified with the developer's signature before installing."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(String(localized: "Check Now")) { u.checkForUpdates(nil); DispatchQueue.main.asyncAfter(deadline: .now() + 2) { lastCheck = u.lastCheck } }
                Spacer()
                VStack(alignment: .trailing) {
                    Text(String(localized: "Version \(version)")).font(.caption)
                    Text(lastCheck.map { String(localized: "Last checked: \(Fmt.date.string(from: $0))") } ?? String(localized: "Never checked"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
    }
}

struct SettingsView: View {
    @StateObject var m = SettingsModel()

    var body: some View {
        TabView {
            Form {
                Picker(String(localized: "Default format for new archives:"), selection: $m.format) {
                    ForEach(CreateFormat.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Picker(String(localized: "Default compression:"), selection: $m.level) {
                    ForEach(CompressionLevel.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker(String(localized: "When a file already exists:"), selection: $m.policy) {
                    Text(String(localized: "Ask")).tag(ConflictPolicy.ask)
                    Text(String(localized: "Replace")).tag(ConflictPolicy.replace)
                    Text(String(localized: "Skip")).tag(ConflictPolicy.skip)
                }
                Toggle(String(localized: "Show extracted files in the Finder"), isOn: $m.openFinder)
            }
            .padding(20)
            .tabItem { Label(String(localized: "General"), systemImage: "gearshape") }

            VStack(alignment: .leading) {
                Text(String(localized: "Folders shown under “Extract to” in the sidebar.")).foregroundStyle(.secondary)
                List(m.favorites, id: \.path) { u in
                    HStack {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: u.path)).resizable().frame(width: 16, height: 16)
                        Text(FileManager.default.displayName(atPath: u.path)); Spacer()
                        Text(u.deletingLastPathComponent().path).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                        Button { if let i = m.favorites.firstIndex(of: u) { Favorites().remove(at: i); m.favorites = Favorites().items } } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                    }
                }
                Button(String(localized: "Add Folder…")) {
                    let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.allowsMultipleSelection = true
                    if p.runModal() == .OK { p.urls.forEach { Favorites().add($0) }; m.favorites = Favorites().items }
                }
            }
            .padding(20)
            .tabItem { Label(String(localized: "Favorites"), systemImage: "star") }

            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "Open these file types with Zzzip when you double-click them:")).foregroundStyle(.secondary)
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading) {
                        ForEach(SupportedTypes.all, id: \.identifier) { t in
                            Toggle(isOn: Binding(get: { m.selectedTypes.contains(t.identifier) },
                                                 set: { on in if on { m.selectedTypes.insert(t.identifier) } else { m.selectedTypes.remove(t.identifier) } })) {
                                Text(t.displayName + (t.isDefaultOn ? "" : " *"))
                            }
                        }
                    }
                }.frame(height: 180)
                Text(String(localized: "* Disk images and installer packages: if you tick them, double-clicking them opens Zzzip instead of mounting or installing.")).font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(String(localized: "Apply")) { apply { try await DefaultAppManager.shared.setZzzipDefault(for: m.chosen) } }
                        .keyboardShortcut(.defaultAction)
                    if DefaultAppManager.shared.kekaURL != nil {
                        Button(String(localized: "Restore Keka")) { apply { try await DefaultAppManager.shared.restoreKeka(for: m.chosen) } }
                    }
                    Spacer()
                    Text(m.status).foregroundStyle(.secondary).font(.caption)
                }
            }
            .padding(20)
            .tabItem { Label(String(localized: "File Types"), systemImage: "doc.zipper") }

            UpdatesSettingsView()
                .tabItem { Label(String(localized: "Updates"), systemImage: "arrow.triangle.2.circlepath") }
        }
        .frame(width: 560, height: 360)
    }

    private func apply(_ op: @escaping () async throws -> Void) {
        Task { @MainActor in
            do { try await op(); m.status = String(localized: "Done.") } catch { m.status = error.localizedDescription }
        }
    }
}

final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()
    init() {
        let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
        w.title = String(localized: "Settings"); w.styleMask = [.titled, .closable]; w.isRestorable = false
        super.init(window: w)
    }
    required init?(coder: NSCoder) { fatalError() }
    func present() { showWindow(nil); window?.center(); NSApp.activate(ignoringOtherApps: true) }
}
