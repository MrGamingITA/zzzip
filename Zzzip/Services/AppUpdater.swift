import AppKit
import Sparkle

enum UpdateInterval: CaseIterable, Equatable {
    case daily, weekly
    var seconds: TimeInterval { self == .daily ? 86_400 : 604_800 }
    init(seconds: TimeInterval) { self = seconds >= 604_800 ? .weekly : .daily }
    var title: String { self == .daily ? String(localized: "Every day") : String(localized: "Every week") }
}

/// Automatic updates from GitHub Releases via Sparkle (appcast.xml in the repo, EdDSA-signed DMGs).
final class AppUpdater: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = AppUpdater()
    private var controller: SPUStandardUpdaterController!

    var updater: SPUUpdater { controller.updater }

    private static var isRunningTests: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: !Self.isRunningTests, updaterDelegate: self, userDriverDelegate: nil)
    }

    /// Developer override (`defaults write io.github.mrgamingita.zzzip ZzzipFeedURL <url>`) used to test updates locally.
    static func feedOverride(defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: "ZzzipFeedURL").flatMap { $0.isEmpty ? nil : $0 }
    }

    func feedURLString(for updater: SPUUpdater) -> String? { Self.feedOverride() }

    var automaticallyChecks: Bool {
        get { updater.automaticallyChecksForUpdates }
        set { objectWillChange.send(); updater.automaticallyChecksForUpdates = newValue }
    }
    var automaticallyDownloads: Bool {
        get { updater.automaticallyDownloadsUpdates }
        set { objectWillChange.send(); updater.automaticallyDownloadsUpdates = newValue }
    }
    var interval: UpdateInterval {
        get { UpdateInterval(seconds: updater.updateCheckInterval) }
        set { objectWillChange.send(); updater.updateCheckInterval = newValue.seconds }
    }
    var lastCheck: Date? { updater.lastUpdateCheckDate }
    var canCheck: Bool { updater.canCheckForUpdates }

    @objc func checkForUpdates(_ sender: Any?) { controller.checkForUpdates(sender) }
}
