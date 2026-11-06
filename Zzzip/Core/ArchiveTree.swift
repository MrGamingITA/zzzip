import Foundation

final class ArchiveNode {
    let name: String
    let path: String
    var isFolder: Bool
    var entry: ArchiveEntry?
    var children: [ArchiveNode] = []
    weak var parent: ArchiveNode?
    var totalSize: UInt64 = 0
    var totalPacked: UInt64 = 0
    /// Files (not folders) at or below this node, computed once when the tree is built.
    var fileCount = 0
    fileprivate var childIndex: [String: ArchiveNode] = [:]

    init(name: String, path: String, isFolder: Bool, entry: ArchiveEntry? = nil) {
        self.name = name; self.path = path; self.isFolder = isFolder; self.entry = entry
    }

    /// The path to pass to 7zz for this node.
    var archivePath: String { entry?.path ?? path }

    var isRoot: Bool { parent == nil }

    func node(atPath p: String) -> ArchiveNode? {
        let comps = ArchiveTree.components(p)
        var n: ArchiveNode = self
        for c in comps { guard let next = n.childIndex[c] else { return nil }; n = next }
        return n
    }

    var allDescendantFiles: [ArchiveNode] {
        children.flatMap { $0.isFolder ? $0.allDescendantFiles : [$0] }
    }

    var folderChildren: [ArchiveNode] { children.filter(\.isFolder) }

    /// Keeps the order, dropping any node that sits inside another selected folder.
    static func removingDescendants(_ nodes: [ArchiveNode]) -> [ArchiveNode] {
        let ids = Set(nodes.map { ObjectIdentifier($0) })
        return nodes.filter { n in
            var p = n.parent
            while let q = p { if ids.contains(ObjectIdentifier(q)) { return false }; p = q.parent }
            return true
        }
    }
}

enum ArchiveTree {
    static func components(_ p: String) -> [String] {
        p.split(separator: "/", omittingEmptySubsequences: true).map(String.init).filter { $0 != "." }
    }

    static func build(_ entries: [ArchiveEntry]) -> ArchiveNode {
        let root = ArchiveNode(name: "", path: "", isFolder: true)
        for e in entries {
            let comps = components(e.path)
            guard !comps.isEmpty else { continue }
            var n = root
            var currentPath = ""
            for (i, c) in comps.enumerated() {
                currentPath = currentPath.isEmpty ? c : currentPath + "/" + c
                let last = i == comps.count - 1
                if let existing = n.childIndex[c] {
                    if last { existing.entry = e; existing.isFolder = existing.isFolder || e.isFolder }
                    n = existing
                } else {
                    let child = ArchiveNode(name: c, path: currentPath, isFolder: last ? e.isFolder : true, entry: last ? e : nil)
                    child.parent = n
                    n.childIndex[c] = child
                    n.children.append(child)
                    n = child
                }
            }
        }
        finalize(root)
        return root
    }

    @discardableResult
    private static func finalize(_ n: ArchiveNode) -> (UInt64, UInt64) {
        if !n.isFolder {
            n.totalSize = n.entry?.size ?? 0; n.totalPacked = n.entry?.packedSize ?? 0; n.fileCount = 1
            return (n.totalSize, n.totalPacked)
        }
        var s: UInt64 = 0, p: UInt64 = 0
        var files = 0
        for c in n.children { let (a, b) = finalize(c); s += a; p += b; files += c.fileCount }
        n.totalSize = s; n.totalPacked = p; n.fileCount = files
        n.children.sort { a, b in
            if a.isFolder != b.isFolder { return a.isFolder }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        return (s, p)
    }
}
