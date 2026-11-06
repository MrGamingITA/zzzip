import AppKit

/// Items shown in the "Extract to" section.
final class DestinationItem: NSObject {
    enum Kind: Equatable { case builtin(BuiltinDestination), favorite(URL), addFolder }
    let kind: Kind
    init(_ kind: Kind) { self.kind = kind }

    func url(archive: URL) -> URL? {
        switch kind {
        case .builtin(let b): return b.url(archive: archive)
        case .favorite(let u): return u
        case .addFolder: return nil
        }
    }

    var title: String {
        switch kind {
        case .builtin(let b): return b.title
        case .favorite(let u): return FileManager.default.displayName(atPath: u.path)
        case .addFolder: return String(localized: "Add Folder…")
        }
    }

    var image: NSImage? {
        switch kind {
        case .builtin(let b): return NSImage(systemSymbolName: b.symbolName, accessibilityDescription: nil)
        case .favorite: return NSImage(systemSymbolName: "star", accessibilityDescription: nil)
        case .addFolder: return NSImage(systemSymbolName: "plus.circle", accessibilityDescription: nil)
        }
    }
}

final class SidebarSection: NSObject {
    enum Kind { case archive, extractTo }
    let kind: Kind
    init(_ k: Kind) { kind = k }
    var title: String { kind == .archive ? String(localized: "Archive") : String(localized: "Extract to") }
}

protocol SidebarDelegate: AnyObject {
    func sidebarDidSelectFolder(_ node: ArchiveNode)
    func sidebarDidClickDestination(_ item: DestinationItem)
    func sidebarDidDropRows(_ paths: [String], on item: DestinationItem)
    func sidebarAddFavorite()
}

extension NSPasteboard.PasteboardType {
    static let zzzipRows = NSPasteboard.PasteboardType("io.github.mrgamingita.zzzip.internal-rows")
}

final class SidebarController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    weak var delegate: SidebarDelegate?
    let outline = NSOutlineView()
    let favorites = Favorites()
    private let archiveSection = SidebarSection(.archive)
    private let destSection = SidebarSection(.extractTo)
    private var rootNode: ArchiveNode?
    private var archiveName = ""
    private var destinations: [DestinationItem] = []
    private var suppressSelection = false

    override func loadView() {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        outline.headerView = nil
        outline.style = .sourceList
        outline.floatsGroupRows = false
        outline.rowSizeStyle = .default
        let col = NSTableColumn(identifier: .init("main"))
        outline.addTableColumn(col)
        outline.outlineTableColumn = col
        outline.dataSource = self
        outline.delegate = self
        outline.target = self
        outline.action = #selector(clicked)
        outline.registerForDraggedTypes([.zzzipRows])
        outline.setDraggingSourceOperationMask(.move, forLocal: true)
        let menu = NSMenu(); menu.delegate = self; outline.menu = menu
        scroll.documentView = outline
        view = scroll
        reloadDestinations()
        NotificationCenter.default.addObserver(self, selector: #selector(favoritesChanged), name: Favorites.didChange, object: nil)
    }

    @objc private func favoritesChanged() { reloadDestinations() }

    func reloadDestinations() {
        destinations = BuiltinDestination.allCases.map { DestinationItem(.builtin($0)) }
            + favorites.items.map { DestinationItem(.favorite($0)) }
            + [DestinationItem(.addFolder)]
        outline.reloadItem(destSection, reloadChildren: true)
        outline.expandItem(destSection)
    }

    func setArchive(root: ArchiveNode, name: String) {
        rootNode = root; archiveName = name
        outline.reloadData()
        outline.expandItem(archiveSection)
        outline.expandItem(root)
        outline.expandItem(destSection)
    }

    func select(folder: ArchiveNode) {
        var chain: [ArchiveNode] = []
        var n: ArchiveNode? = folder.parent
        while let p = n { chain.insert(p, at: 0); n = p.parent }
        chain.forEach { outline.expandItem($0) }
        let row = outline.row(forItem: folder)
        suppressSelection = true
        if row >= 0 { outline.selectRowIndexes([row], byExtendingSelection: false); outline.scrollRowToVisible(row) }
        suppressSelection = false
    }

    // MARK: data source

    func outlineView(_ ov: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        switch item {
        case nil: return 2
        case let s as SidebarSection: return s.kind == .archive ? (rootNode == nil ? 0 : 1) : destinations.count
        case let n as ArchiveNode: return n.folderChildren.count
        default: return 0
        }
    }

    func outlineView(_ ov: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        switch item {
        case nil: return index == 0 ? archiveSection : destSection
        case let s as SidebarSection: return s.kind == .archive ? rootNode! : destinations[index]
        case let n as ArchiveNode: return n.folderChildren[index]
        default: fatalError()
        }
    }

    func outlineView(_ ov: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if item is SidebarSection { return true }
        if let n = item as? ArchiveNode { return !n.folderChildren.isEmpty }
        return false
    }

    func outlineView(_ ov: NSOutlineView, isGroupItem item: Any) -> Bool { item is SidebarSection }
    func outlineView(_ ov: NSOutlineView, shouldSelectItem item: Any) -> Bool { !(item is SidebarSection) }
    func outlineView(_ ov: NSOutlineView, shouldShowOutlineCellForItem item: Any) -> Bool { !(item is SidebarSection) }

    func outlineView(_ ov: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        if let s = item as? SidebarSection {
            let tf = NSTextField(labelWithString: s.title.uppercased())
            tf.font = .systemFont(ofSize: 11, weight: .semibold); tf.textColor = .secondaryLabelColor
            let cell = NSTableCellView(); cell.addSubview(tf); cell.textField = tf
            tf.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([tf.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2), tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor)])
            return cell
        }
        let cell = NSTableCellView()
        let iv = NSImageView(); let tf = NSTextField(labelWithString: "")
        tf.lineBreakMode = .byTruncatingMiddle
        cell.addSubview(iv); cell.addSubview(tf); cell.imageView = iv; cell.textField = tf
        iv.translatesAutoresizingMaskIntoConstraints = false; tf.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iv.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2), iv.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            iv.widthAnchor.constraint(equalToConstant: 16), iv.heightAnchor.constraint(equalToConstant: 16),
            tf.leadingAnchor.constraint(equalTo: iv.trailingAnchor, constant: 6), tf.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
            tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor)])
        if let n = item as? ArchiveNode {
            tf.stringValue = n.isRoot ? archiveName : n.name
            iv.image = n.isRoot ? NSImage(systemSymbolName: "archivebox", accessibilityDescription: nil) : NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
            iv.contentTintColor = n.isRoot ? .systemPurple : .systemBlue
        } else if let d = item as? DestinationItem {
            tf.stringValue = d.title; iv.image = d.image
            iv.contentTintColor = d.kind == .addFolder ? .controlAccentColor : .secondaryLabelColor
            if d.kind == .addFolder { tf.textColor = .controlAccentColor }
            if case .favorite(let u) = d.kind { cell.toolTip = u.path }
        }
        return cell
    }

    @objc private func clicked() {
        let item = outline.item(atRow: outline.clickedRow)
        if let d = item as? DestinationItem {
            if d.kind == .addFolder { delegate?.sidebarAddFavorite() } else { delegate?.sidebarDidClickDestination(d) }
            restoreFolderSelection()
        }
    }

    private var lastFolder: ArchiveNode?
    private func restoreFolderSelection() { if let f = lastFolder { select(folder: f) } else { outline.deselectAll(nil) } }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !suppressSelection, let n = outline.item(atRow: outline.selectedRow) as? ArchiveNode else { return }
        lastFolder = n
        delegate?.sidebarDidSelectFolder(n)
    }

    // MARK: drag & drop (rows from the file list onto destinations; reorder favorites)

    func outlineView(_ ov: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        guard let d = item as? DestinationItem, case .favorite(let u) = d.kind else { return nil }
        let pb = NSPasteboardItem(); pb.setString(u.path, forType: .init("io.github.mrgamingita.zzzip.favorite")); return pb
    }

    func outlineView(_ ov: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        let pb = info.draggingPasteboard
        if pb.availableType(from: [.zzzipRows]) != nil {
            guard let d = item as? DestinationItem, d.kind != .addFolder, index == NSOutlineViewDropOnItemIndex else { return [] }
            return .copy
        }
        return []
    }

    func outlineView(_ ov: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        guard let d = item as? DestinationItem,
              let s = info.draggingPasteboard.string(forType: .zzzipRows),
              let paths = try? JSONDecoder().decode([String].self, from: Data(s.utf8)) else { return false }
        delegate?.sidebarDidDropRows(paths, on: d)
        return true
    }
}

extension SidebarController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let d = outline.item(atRow: outline.clickedRow) as? DestinationItem, case .favorite(let u) = d.kind else { return }
        let idx = favorites.items.firstIndex(of: u) ?? 0
        let rm = menu.addItem(withTitle: String(localized: "Remove from Favorites"), action: #selector(removeFavorite(_:)), keyEquivalent: "")
        rm.representedObject = idx; rm.target = self
        if idx > 0 { let up = menu.addItem(withTitle: String(localized: "Move Up"), action: #selector(moveFavorite(_:)), keyEquivalent: ""); up.representedObject = [idx, idx - 1]; up.target = self }
        if idx < favorites.items.count - 1 { let dn = menu.addItem(withTitle: String(localized: "Move Down"), action: #selector(moveFavorite(_:)), keyEquivalent: ""); dn.representedObject = [idx, idx + 1]; dn.target = self }
        let show = menu.addItem(withTitle: String(localized: "Show in Finder"), action: #selector(showFavorite(_:)), keyEquivalent: ""); show.representedObject = u; show.target = self
    }
    @objc private func removeFavorite(_ s: NSMenuItem) { favorites.remove(at: s.representedObject as! Int) }
    @objc private func moveFavorite(_ s: NSMenuItem) { let a = s.representedObject as! [Int]; favorites.move(from: a[0], to: a[1]) }
    @objc private func showFavorite(_ s: NSMenuItem) { NSWorkspace.shared.activateFileViewerSelecting([s.representedObject as! URL]) }
}
