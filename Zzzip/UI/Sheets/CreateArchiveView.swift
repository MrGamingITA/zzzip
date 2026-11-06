import SwiftUI
import AppKit

final class CreateArchiveModel: ObservableObject {
    @Published var sources: [URL]
    @Published var name: String
    @Published var destinationChoice: String = "beside"   // "beside", favorite path, or "custom"
    @Published var customDestination: URL?
    @Published var format: CreateFormat
    @Published var level: CompressionLevel
    @Published var password = ""
    @Published var confirm = ""
    @Published var encryptNames = false
    @Published var volumeChoice = 0          // 0 none, 1 100MB, 2 700MB, 3 4GB, 4 custom
    @Published var customVolumeMB = "1024"
    @Published var excludeMacFiles = true
    @Published var trashOriginals = false
    @Published var showAdvanced = false

    init(sources: [URL]) {
        self.sources = sources
        let last = Settings.lastCreateOptions
        name = ArchiveCreator.defaultName(for: sources)
        format = last?.format ?? Settings.defaultFormat
        level = last?.level ?? Settings.defaultLevel
        excludeMacFiles = last?.excludeMacFiles ?? true
        encryptNames = last?.encryptNames ?? false
    }

    var besideURL: URL { sources.first?.deletingLastPathComponent() ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0] }

    var destination: URL? {
        switch destinationChoice {
        case "beside": return besideURL
        case "custom": return customDestination
        default: return URL(fileURLWithPath: destinationChoice)
        }
    }

    var volumeSize: UInt64? {
        switch volumeChoice {
        case 1: return 100 * 1024 * 1024
        case 2: return 700 * 1024 * 1024
        case 3: return 4 * 1024 * 1024 * 1024
        case 4: return UInt64(customVolumeMB.trimmingCharacters(in: .whitespaces)).map { $0 * 1024 * 1024 }
        default: return nil
        }
    }

    var passwordMismatch: Bool { format.supportsPassword && password != confirm }
    var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !name.contains("/") && destination != nil && !passwordMismatch && !sources.isEmpty
            && (volumeChoice != 4 || volumeSize != nil)
    }

    var options: CreateOptions? {
        guard let destination else { return nil }
        var o = CreateOptions(name: name.trimmingCharacters(in: .whitespaces), destination: destination, format: format, level: level)
        o.password = format.supportsPassword && !password.isEmpty ? password : nil
        o.encryptNames = format.supportsEncryptedNames && encryptNames && o.password != nil
        o.volumeSize = volumeSize
        o.excludeMacFiles = excludeMacFiles
        o.trashOriginals = trashOriginals
        return o
    }
}

struct CreateArchiveView: View {
    @ObservedObject var model: CreateArchiveModel
    let favorites: [URL]
    let onCancel: () -> Void
    let onCreate: (CreateOptions) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(nsImage: AppIcon.image).resizable().frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "New Archive")).font(.headline)
                    Text(model.sources.count == 1 ? model.sources[0].lastPathComponent : String(localized: "\(model.sources.count) items"))
                        .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
            Form {
                TextField(String(localized: "Name:"), text: $model.name)
                Picker(String(localized: "Save to:"), selection: $model.destinationChoice) {
                    Text(String(localized: "Beside the Originals")).tag("beside")
                    if !favorites.isEmpty {
                        Divider()
                        ForEach(favorites, id: \.path) { Text(FileManager.default.displayName(atPath: $0.path)).tag($0.path) }
                    }
                    Divider()
                    Text(model.customDestination.map { FileManager.default.displayName(atPath: $0.path) } ?? String(localized: "Choose…")).tag("custom")
                }
                .onChange(of: model.destinationChoice) { _, v in if v == "custom" { chooseFolder() } }
                Picker(String(localized: "Format:"), selection: $model.format) {
                    ForEach(CreateFormat.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Picker(String(localized: "Compression:"), selection: $model.level) {
                    ForEach(CompressionLevel.allCases, id: \.self) { Text($0.title).tag($0) }
                }.disabled(!model.format.supportsLevel)
                if model.format.supportsPassword {
                    SecureField(String(localized: "Password:"), text: $model.password)
                    SecureField(String(localized: "Confirm:"), text: $model.confirm)
                    if model.passwordMismatch && !model.confirm.isEmpty {
                        Text(String(localized: "The passwords don't match.")).foregroundStyle(.red).font(.caption)
                    }
                    if model.format.supportsEncryptedNames {
                        Toggle(String(localized: "Encrypt file names too"), isOn: $model.encryptNames).disabled(model.password.isEmpty)
                    }
                } else {
                    Text(String(localized: "This format doesn't support passwords.")).foregroundStyle(.secondary).font(.caption)
                }
            }
            DisclosureGroup(String(localized: "Advanced"), isExpanded: $model.showAdvanced) {
                Form {
                    Picker(String(localized: "Split into volumes:"), selection: $model.volumeChoice) {
                        Text(String(localized: "Don't split")).tag(0)
                        Text("100 MB").tag(1); Text("700 MB").tag(2); Text("4 GB").tag(3)
                        Text(String(localized: "Custom…")).tag(4)
                    }
                    if model.volumeChoice == 4 {
                        HStack { TextField("MB", text: $model.customVolumeMB).frame(width: 90); Text("MB") }
                    }
                    Toggle(String(localized: "Exclude Mac files (.DS_Store, __MACOSX…)"), isOn: $model.excludeMacFiles)
                    Toggle(String(localized: "Move originals to the Trash afterwards"), isOn: $model.trashOriginals)
                }.padding(.top, 6)
            }
            HStack {
                Spacer()
                Button(String(localized: "Cancel"), action: onCancel).keyboardShortcut(.cancelAction)
                Button(String(localized: "Create")) { if let o = model.options { onCreate(o) } }
                    .keyboardShortcut(.defaultAction).disabled(!model.canCreate)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func chooseFolder() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
        p.directoryURL = model.besideURL
        if p.runModal() == .OK, let u = p.url { model.customDestination = u } else if model.customDestination == nil { model.destinationChoice = "beside" }
    }
}
