import SwiftUI

struct InfoView: View {
    let url: URL
    let info: ArchiveInfo
    let root: ArchiveNode
    let encrypted: Bool
    let typeLabel: String
    let close: () -> Void

    var body: some View {
        let files = root.allDescendantFiles.count
        let folders = info.entries.filter(\.isFolder).count
        let ratio = root.totalSize > 0 ? Double(root.totalPacked) / Double(root.totalSize) * 100 : 0
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 48, height: 48)
                VStack(alignment: .leading) {
                    Text(url.lastPathComponent).font(.headline).lineLimit(2)
                    Text(typeLabel).foregroundStyle(.secondary)
                }
            }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                row(String(localized: "Files"), "\(files)")
                row(String(localized: "Folders"), "\(folders)")
                row(String(localized: "Size"), Fmt.bytes(root.totalSize))
                row(String(localized: "Packed"), Fmt.bytes(root.totalPacked))
                row(String(localized: "Archive Size"), Fmt.bytes(UInt64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? Int(info.physicalSize ?? 0))))
                row(String(localized: "Ratio"), String(format: "%.1f %%", ratio))
                row(String(localized: "Encrypted"), encrypted ? String(localized: "Yes") : String(localized: "No"))
                row(String(localized: "Volumes"), info.volumeCount.map(String.init) ?? "1")
                row(String(localized: "Path"), url.path)
            }
            HStack { Spacer(); Button(String(localized: "OK"), action: close).keyboardShortcut(.defaultAction) }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func row(_ k: String, _ v: String) -> some View {
        GridRow {
            Text(k).foregroundStyle(.secondary)
            Text(v).textSelection(.enabled).lineLimit(3)
        }
    }
}
