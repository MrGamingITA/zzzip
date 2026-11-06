import AppKit
import UniformTypeIdentifiers

final class DefaultAppManager {
    static let shared = DefaultAppManager()
    var appURL: URL { Bundle.main.bundleURL }
    var kekaURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.aone.keka") }

    func isZzzipDefault(_ t: SupportedType) -> Bool {
        guard let ut = UTType(t.identifier), let u = NSWorkspace.shared.urlForApplication(toOpen: ut) else { return false }
        return u.resolvingSymlinksInPath().path == appURL.resolvingSymlinksInPath().path
            || Bundle(url: u)?.bundleIdentifier == Bundle.main.bundleIdentifier
    }

    var isDefaultForZip: Bool { SupportedTypes.all.first.map(isZzzipDefault) ?? false }

    func setDefault(app: URL, for types: [SupportedType]) async throws {
        for t in types {
            guard let ut = UTType(t.identifier) else { continue }
            try await NSWorkspace.shared.setDefaultApplication(at: app, toOpen: ut)
        }
    }

    func setZzzipDefault(for types: [SupportedType]) async throws { try await setDefault(app: appURL, for: types) }

    func restoreKeka(for types: [SupportedType]) async throws {
        guard let k = kekaURL else { return }
        try await setDefault(app: k, for: types)
    }
}
