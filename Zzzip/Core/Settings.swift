import Foundation

enum ConflictPolicy: String, CaseIterable { case ask, replace, skip }

enum Settings {
    static var d: UserDefaults { .standard }

    static var conflictPolicy: ConflictPolicy {
        get { ConflictPolicy(rawValue: d.string(forKey: "conflictPolicy") ?? "") ?? .ask }
        set { d.set(newValue.rawValue, forKey: "conflictPolicy") }
    }
    static var openFinderAfterExtract: Bool {
        get { d.bool(forKey: "openFinderAfterExtract") }
        set { d.set(newValue, forKey: "openFinderAfterExtract") }
    }
    static var defaultFormat: CreateFormat {
        get { CreateFormat(rawValue: d.string(forKey: "defaultFormat") ?? "") ?? .zip }
        set { d.set(newValue.rawValue, forKey: "defaultFormat") }
    }
    static var defaultLevel: CompressionLevel {
        get { d.object(forKey: "defaultLevel").flatMap { CompressionLevel(rawValue: $0 as? Int ?? -1) } ?? .normal }
        set { d.set(newValue.rawValue, forKey: "defaultLevel") }
    }
    /// Last options used in the create sheet (never includes the password).
    static var lastCreateOptions: CreateOptions? {
        get { d.data(forKey: "lastCreateOptions").flatMap { try? JSONDecoder().decode(CreateOptions.self, from: $0) } }
        set { var v = newValue; v?.password = nil; d.set(v.flatMap { try? JSONEncoder().encode($0) }, forKey: "lastCreateOptions") }
    }
}
