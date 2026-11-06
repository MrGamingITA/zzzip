import Foundation

final class Favorites {
    static let didChange = Notification.Name("ZzzipFavoritesDidChange")
    private let defaults: UserDefaults
    private let key = "favorites"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var items: [URL] {
        stored.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private var stored: [String] {
        get { defaults.stringArray(forKey: key) ?? [] }
        set { defaults.set(newValue, forKey: key); NotificationCenter.default.post(name: Self.didChange, object: nil) }
    }

    func add(_ url: URL) {
        let p = url.standardizedFileURL.path
        guard !stored.contains(p) else { return }
        stored = stored + [p]
    }

    func remove(at index: Int) {
        var s = items.map(\.path); guard s.indices.contains(index) else { return }
        s.remove(at: index); stored = s
    }

    func move(from: Int, to: Int) {
        var s = items.map(\.path); guard s.indices.contains(from) else { return }
        let v = s.remove(at: from); s.insert(v, at: min(max(to, 0), s.count)); stored = s
    }
}

enum BuiltinDestination: CaseIterable {
    case besideArchive, desktop, downloads, documents

    func url(archive: URL?) -> URL {
        let fm = FileManager.default
        switch self {
        case .besideArchive: return archive?.deletingLastPathComponent() ?? fm.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        case .desktop: return fm.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        case .downloads: return fm.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        case .documents: return fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        }
    }

    var title: String {
        switch self {
        case .besideArchive: return String(localized: "Beside the Archive")
        case .desktop: return String(localized: "Desktop")
        case .downloads: return String(localized: "Downloads")
        case .documents: return String(localized: "Documents")
        }
    }

    var symbolName: String {
        switch self {
        case .besideArchive: return "folder"
        case .desktop: return "menubar.dock.rectangle"
        case .downloads: return "arrow.down.circle"
        case .documents: return "doc"
        }
    }
}
