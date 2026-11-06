import AppKit

protocol FileListDelegate: AnyObject {
    func fileListOpen(_ node: ArchiveNode)
    func fileListGoUp()
    func fileListSelectionChanged()
    func fileListPreview()
    func fileListPromiseProvider(for node: ArchiveNode) -> NSPasteboardWriting?
    func fileListDropFiles(_ urls: [URL]) -> Bool
    var fileListAcceptsDrops: Bool { get }
    func fileListContextMenu() -> NSMenu?
}

final class FileTableView: NSTableView {
    weak var listController: FileListController?
    override func keyDown(with e: NSEvent) {
        if e.charactersIgnoringModifiers == " " { listController?.delegate?.fileListPreview(); return }
        if e.keyCode == 36 || e.keyCode == 76 { listController?.openSelected(); return }   // Return / Enter
        if e.keyCode == 126 && e.modifierFlags.contains(.command) { listController?.delegate?.fileListGoUp(); return }
        if e.keyCode == 125 && e.modifierFlags.contains(.command) { listController?.openSelected(); return }
        super.keyDown(with: e)
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        let row = self.row(at: convert(event.locationInWindow, from: nil))
        if row >= 0 && !selectedRowIndexes.contains(row) { selectRowIndexes([row], byExtendingSelection: false) }
        return listController?.delegate?.fileListContextMenu()
    }
}

final class FileListController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    enum Row { case parent, node(ArchiveNode) }

    weak var delegate: FileListDelegate?
    let table = FileTableView()
    private(set) var rows: [Row] = []
    private var folder: ArchiveNode?
    private var searchResults: [ArchiveNode]?

    var selectedNodes: [ArchiveNode] {
        table.selectedRowIndexes.compactMap { i in if case .node(let n) = rows[i] { return n } else { return nil } }
    }
    var isSearching: Bool { searchResults != nil }

    override func loadView() {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        table.listController = self
        table.style = .fullWidth
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = true
        table.allowsColumnReordering = true
        // The Name column absorbs width changes, so the other columns are never pushed past the right edge.
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.rowHeight = 22
        for (id, title, width) in [("name", String(localized: "Name"), 300.0), ("folder", String(localized: "Folder"), 160.0),
                                   ("size", String(localized: "Size"), 80.0), ("packed", String(localized: "Packed"), 80.0),
                                   ("kind", String(localized: "Kind"), 140.0), ("modified", String(localized: "Modified"), 130.0)] {
            let c = NSTableColumn(identifier: .init(id))
            c.title = title; c.width = width; c.minWidth = 50
            c.sortDescriptorPrototype = NSSortDescriptor(key: id, ascending: true)
            if id == "size" || id == "packed" { c.headerCell.alignment = .right }
            table.addTableColumn(c)
        }
        table.tableColumn(withIdentifier: .init("folder"))?.isHidden = true
        table.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        table.dataSource = self; table.delegate = self
        table.target = self; table.doubleAction = #selector(doubleClicked)
        table.setDraggingSourceOperationMask(.copy, forLocal: false)
        table.setDraggingSourceOperationMask(.copy, forLocal: true)
        table.registerForDraggedTypes([.fileURL])
        table.draggingDestinationFeedbackStyle = .none
        scroll.documentView = table
        view = scroll
    }

    private var didSetPreferredWidths = false
    override func viewDidLayout() {
        super.viewDidLayout()
        guard let clip = table.enclosingScrollView?.contentView, clip.bounds.width > 0 else { return }
        let others = table.tableColumns.filter { $0.identifier.rawValue != "name" && !$0.isHidden }
        if !didSetPreferredWidths {
            didSetPreferredWidths = true
            let preferred: [String: CGFloat] = ["size": 80, "packed": 80, "kind": 130, "modified": 150, "folder": 160]
            for c in others { c.width = preferred[c.identifier.rawValue] ?? c.width }
        }
        // The Name column takes whatever is left, so the other columns never fall off the right edge.
        let used = others.reduce(CGFloat(0)) { $0 + $1.width + table.intercellSpacing.width }
        let name = max(160, clip.bounds.width - used - table.intercellSpacing.width - 2)
        if let col = table.tableColumn(withIdentifier: .init("name")), abs(col.width - name) > 0.5 { col.width = name }
    }

    func show(folder: ArchiveNode) {
        self.folder = folder; searchResults = nil
        table.tableColumn(withIdentifier: .init("folder"))?.isHidden = true
        rebuild()
        table.deselectAll(nil)
        table.scrollRowToVisible(0)
    }

    func showSearch(results: [ArchiveNode]) {
        searchResults = results
        table.tableColumn(withIdentifier: .init("folder"))?.isHidden = false
        rebuild(); table.deselectAll(nil)
    }

    func rebuild() {
        let previouslySelected = Set(selectedNodes.map(\.path))
        var nodes = searchResults ?? folder?.children ?? []
        nodes.sort(by: comparator())
        rows = (searchResults == nil && folder?.isRoot == false ? [Row.parent] : []) + nodes.map { .node($0) }
        table.reloadData()
        let idx = IndexSet(rows.indices.filter { if case .node(let n) = rows[$0] { return previouslySelected.contains(n.path) }; return false })
        table.selectRowIndexes(idx, byExtendingSelection: false)
        delegate?.fileListSelectionChanged()
    }

    func select(path: String) {
        if let i = rows.firstIndex(where: { if case .node(let n) = $0 { return n.path == path }; return false }) {
            table.selectRowIndexes([i], byExtendingSelection: false); table.scrollRowToVisible(i)
        }
    }

    private func comparator() -> (ArchiveNode, ArchiveNode) -> Bool {
        let sd = table.sortDescriptors.first ?? NSSortDescriptor(key: "name", ascending: true)
        let asc = sd.ascending, key = sd.key ?? "name"
        return { a, b in
            if a.isFolder != b.isFolder { return a.isFolder }
            let r: ComparisonResult
            switch key {
            case "size": r = a.totalSize == b.totalSize ? .orderedSame : (a.totalSize < b.totalSize ? .orderedAscending : .orderedDescending)
            case "packed": r = a.totalPacked == b.totalPacked ? .orderedSame : (a.totalPacked < b.totalPacked ? .orderedAscending : .orderedDescending)
            case "kind": r = Fmt.kind(a).localizedStandardCompare(Fmt.kind(b))
            case "modified":
                let da = a.entry?.modified ?? .distantPast, db = b.entry?.modified ?? .distantPast
                r = da == db ? .orderedSame : (da < db ? .orderedAscending : .orderedDescending)
            case "folder": r = (a.parent?.path ?? "").localizedStandardCompare(b.parent?.path ?? "")
            default: r = a.name.localizedStandardCompare(b.name)
            }
            if r == .orderedSame { return a.name.localizedStandardCompare(b.name) == .orderedAscending }
            return asc ? r == .orderedAscending : r == .orderedDescending
        }
    }

    // MARK: actions

    @objc private func doubleClicked() {
        guard table.clickedRow >= 0 else { return }
        openRow(table.clickedRow)
    }

    func openSelected() { if let i = table.selectedRowIndexes.first { openRow(i) } }

    private func openRow(_ i: Int) {
        switch rows[i] {
        case .parent: delegate?.fileListGoUp()
        case .node(let n): delegate?.fileListOpen(n)
        }
    }

    // MARK: table

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) { rebuild() }

    func tableViewSelectionDidChange(_ notification: Notification) { delegate?.fileListSelectionChanged() }

    func tableView(_ tv: NSTableView, viewFor col: NSTableColumn?, row: Int) -> NSView? {
        guard let id = col?.identifier.rawValue else { return nil }
        let cell = NSTableCellView()
        let tf = NSTextField(labelWithString: "")
        tf.lineBreakMode = .byTruncatingMiddle
        tf.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(tf); cell.textField = tf
        var leading: NSLayoutXAxisAnchor = cell.leadingAnchor
        if id == "name" {
            let iv = NSImageView(); iv.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(iv); cell.imageView = iv
            NSLayoutConstraint.activate([iv.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4), iv.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                                         iv.widthAnchor.constraint(equalToConstant: 16), iv.heightAnchor.constraint(equalToConstant: 16)])
            leading = iv.trailingAnchor
        }
        NSLayoutConstraint.activate([tf.leadingAnchor.constraint(equalTo: leading, constant: 6), tf.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                                     tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor)])
        switch rows[row] {
        case .parent:
            if id == "name" { tf.stringValue = ".."; cell.imageView?.image = NSImage(systemSymbolName: "arrow.turn.left.up", accessibilityDescription: nil) }
        case .node(let n):
            switch id {
            case "name":
                tf.stringValue = n.name; cell.imageView?.image = Fmt.icon(n)
                if n.entry?.isEncrypted == true { tf.stringValue += " 🔒" }
            case "folder": tf.stringValue = n.parent?.path ?? ""
            case "size": tf.stringValue = Fmt.bytes(n.totalSize); tf.alignment = .right
            case "packed": tf.stringValue = n.entry?.packedSize == nil && !n.isFolder ? "—" : Fmt.bytes(n.totalPacked); tf.alignment = .right
            case "kind": tf.stringValue = Fmt.kind(n); tf.lineBreakMode = .byTruncatingTail
            case "modified": tf.stringValue = n.entry?.modified.map { Fmt.date.string(from: $0) } ?? ""
            default: break
            }
            if id != "name" { tf.textColor = .secondaryLabelColor }
        }
        return cell
    }

    // MARK: drag out

    func tableView(_ tv: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard case .node(let n) = rows[row] else { return nil }
        return delegate?.fileListPromiseProvider(for: n)
    }

    func tableView(_ tv: NSTableView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint, forRowIndexes rowIndexes: IndexSet) {
        // Also carry the internal paths so the sidebar's "Extract to" entries can accept the drop.
        let paths = rowIndexes.compactMap { i -> String? in if case .node(let n) = rows[i] { return n.path } else { return nil } }
        if let data = try? JSONEncoder().encode(paths) {
            session.draggingPasteboard.addTypes([.zzzipRows], owner: nil)
            session.draggingPasteboard.setString(String(decoding: data, as: UTF8.self), forType: .zzzipRows)
        }
    }

    // MARK: drop in (add files)

    func tableView(_ tv: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation op: NSTableView.DropOperation) -> NSDragOperation {
        guard (info.draggingSource as? NSTableView) !== table, delegate?.fileListAcceptsDrops == true,
              info.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) else { return [] }
        tv.setDropRow(-1, dropOperation: .on)
        return .copy
    }

    func tableView(_ tv: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] else { return false }
        return delegate?.fileListDropFiles(urls) ?? false
    }
}
