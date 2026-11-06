import AppKit

extension NSToolbarItem.Identifier {
    static let extractTo = Self("extractTo"), extractHere = Self("extractHere"), preview = Self("preview"), open = Self("open")
    static let add = Self("add"), delete = Self("delete"), test = Self("test"), info = Self("info"), search = Self("search")
}

final class ArchiveWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    var doc: ArchiveDocument { document as! ArchiveDocument }
    let sidebar = SidebarController()
    let fileList = FileListController()
    let pathControl = NSPathControl()
    let upButton = NSButton()
    let statusLeft = NSTextField(labelWithString: "")
    let statusRight = NSTextField(labelWithString: "")
    let bannerHost = NSStackView()
    let spinner = NSProgressIndicator()
    var currentFolder: ArchiveNode?
    var searchField: NSSearchField?
    lazy var session: URL = CacheManager.shared.makeSession()
    let watcher = OpenedFileWatcher()
    var busy = false { didSet { window?.toolbar?.validateVisibleItems() } }
    var closingConfirmed = false
    let busyCounter = BusyCounter()
    let dragRunner = SerialRunner()
    var previewGeneration = 0
    let promiseQueue: OperationQueue = { let q = OperationQueue(); q.qualityOfService = .userInitiated; return q }()

    init(document: ArchiveDocument) {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 640),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        w.minSize = NSSize(width: 720, height: 400)
        w.isRestorable = false
        w.setFrameAutosaveName("ZzzipArchiveWindow")
        w.toolbarStyle = .expanded
        w.titleVisibility = .visible
        super.init(window: w)
        w.delegate = self
        buildToolbar()
        buildContent()
        w.center()
        NotificationCenter.default.addObserver(self, selector: #selector(appBecameActive), name: NSApplication.didBecomeActiveNotification, object: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func windowTitle(forDocumentDisplayName displayName: String) -> String { displayName }

    // MARK: layout

    private func buildToolbar() {
        let tb = NSToolbar(identifier: "ZzzipArchiveToolbar")
        tb.delegate = self
        tb.displayMode = .iconAndLabel
        tb.allowsUserCustomization = true
        tb.autosavesConfiguration = true
        window?.toolbar = tb
    }

    private func buildContent() {
        let split = NSSplitViewController()
        split.splitView.isVertical = true
        let sideItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sideItem.minimumThickness = 190; sideItem.maximumThickness = 340
        sideItem.canCollapse = true
        sidebar.delegate = self

        let content = NSViewController()
        let v = NSView()
        content.view = v
        fileList.delegate = self

        upButton.image = NSImage(systemSymbolName: "arrow.up", accessibilityDescription: String(localized: "Enclosing Folder"))
        upButton.bezelStyle = .accessoryBarAction
        upButton.target = self; upButton.action = #selector(goUp(_:))
        upButton.toolTip = String(localized: "Enclosing Folder")
        pathControl.pathStyle = .standard
        pathControl.isEditable = false
        pathControl.target = self; pathControl.action = #selector(pathClicked(_:))
        pathControl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let pathBar = NSStackView(views: [upButton, pathControl])
        pathBar.orientation = .horizontal; pathBar.spacing = 6
        pathBar.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)

        for l in [statusLeft, statusRight] { l.font = .systemFont(ofSize: 11); l.textColor = .secondaryLabelColor; l.lineBreakMode = .byTruncatingTail }
        statusLeft.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        spinner.style = .spinning; spinner.controlSize = .small; spinner.isDisplayedWhenStopped = false
        let spacer = NSView(); spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let statusBar = NSStackView(views: [statusLeft, spacer, spinner, statusRight])
        statusBar.orientation = .horizontal
        statusBar.edgeInsets = NSEdgeInsets(top: 3, left: 10, bottom: 5, right: 10)

        bannerHost.orientation = .vertical

        let sep1 = NSBox(); sep1.boxType = .separator
        let sep2 = NSBox(); sep2.boxType = .separator
        let stack = NSStackView(views: [bannerHost, pathBar, sep1, fileList.view, sep2, statusBar])
        stack.orientation = .vertical; stack.spacing = 0; stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: v.leadingAnchor), stack.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            stack.topAnchor.constraint(equalTo: v.safeAreaLayoutGuide.topAnchor), stack.bottomAnchor.constraint(equalTo: v.bottomAnchor)])
        for sub in stack.arrangedSubviews { sub.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        fileList.view.setContentHuggingPriority(.init(1), for: .vertical)

        split.addSplitViewItem(sideItem)
        split.addSplitViewItem(NSSplitViewItem(viewController: content))
        window?.contentViewController = split
        window?.setContentSize(NSSize(width: 1040, height: 640))
        window?.initialFirstResponder = fileList.table
    }

    // MARK: loading

    func reload(keepingFolder path: String? = nil) {
        Task { @MainActor in
            spinner.startAnimation(nil)
            defer { spinner.stopAnimation(nil) }
            while true {
                do {
                    try await runWithProgress(title: String(localized: "Opening “\(doc.archiveURL.lastPathComponent)”…")) { _, cancel in
                        try await self.doc.load(cancel: cancel)
                    }
                    break
                } catch let e as EngineError where e == .passwordRequired || e == .wrongPassword {
                    if doc.password == nil { doc.needsHeaderPassword = true }
                    guard let pw = await askPassword(wrong: e == .wrongPassword) else { doc.close(); return }
                    doc.password = pw
                } catch {
                    if (error as? EngineError) == .cancelled { if doc.root == nil { doc.close() }; return }
                    await showError(error)
                    if doc.root == nil { doc.close() }
                    return
                }
            }
            guard let root = doc.root else { return }
            sidebar.setArchive(root: root, name: doc.archiveURL.lastPathComponent)
            let target = path.flatMap { root.node(atPath: $0) }.flatMap { $0.isFolder ? $0 : nil }
                ?? (root.children.count == 1 && root.children[0].isFolder && path == nil ? root : root)
            navigate(to: target)
            window?.toolbar?.validateVisibleItems()
        }
    }

    // MARK: navigation

    func navigate(to folder: ArchiveNode) {
        currentFolder = folder
        if let s = searchField, !s.stringValue.isEmpty { s.stringValue = "" }
        fileList.show(folder: folder)
        sidebar.select(folder: folder)
        updatePath()
        upButton.isEnabled = !folder.isRoot
        updateStatus()
    }

    private func updatePath() {
        guard let f = currentFolder else { return }
        var chain: [ArchiveNode] = []
        var n: ArchiveNode? = f
        while let c = n { chain.insert(c, at: 0); n = c.parent }
        pathControl.pathItems = chain.map { node in
            let item = NSPathControlItem()
            item.title = node.isRoot ? doc.archiveURL.lastPathComponent : node.name
            item.image = node.isRoot ? NSImage(systemSymbolName: "archivebox", accessibilityDescription: nil) : NSWorkspace.shared.icon(for: .folder)
            return item
        }
    }

    @objc func pathClicked(_ sender: NSPathControl) {
        guard let clicked = sender.clickedPathItem, let i = sender.pathItems.firstIndex(of: clicked), let f = currentFolder else { return }
        var chain: [ArchiveNode] = []
        var n: ArchiveNode? = f
        while let c = n { chain.insert(c, at: 0); n = c.parent }
        if chain.indices.contains(i) { navigate(to: chain[i]) }
    }

    @objc func goUp(_ sender: Any?) {
        guard let f = currentFolder, let p = f.parent else { return }
        navigate(to: p)
        fileList.select(path: f.path)
    }

    func updateStatus() {
        let sel = fileList.selectedNodes
        if sel.isEmpty {
            statusLeft.stringValue = doc.isWritable || doc.info == nil ? "" : String(localized: "Read-only format")
        } else {
            let size = sel.reduce(UInt64(0)) { $0 + $1.totalSize }
            statusLeft.stringValue = sel.count == 1 ? String(localized: "“\(sel[0].name)” selected (\(Fmt.bytes(size)))") : String(localized: "\(sel.count) selected (\(Fmt.bytes(size)))")
        }
        guard let root = doc.root, doc.info != nil else { statusRight.stringValue = ""; return }
        let count = root.fileCount
        statusRight.stringValue = String(localized: "\(count) items, \(Fmt.bytes(root.totalSize)) · \(doc.displayType)")
    }

    // MARK: search

    @objc func searchChanged(_ sender: NSSearchField) {
        guard let root = doc.root else { return }
        let q = sender.stringValue.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { if let f = currentFolder { fileList.show(folder: f) }; updateStatus(); return }
        var results: [ArchiveNode] = []
        func walk(_ n: ArchiveNode) { for c in n.children { if c.name.localizedCaseInsensitiveContains(q) { results.append(c) }; if c.isFolder { walk(c) } } }
        walk(root)
        fileList.showSearch(results: results)
        updateStatus()
    }

    @objc func focusSearch(_ sender: Any?) {
        guard let s = searchField else { return }
        if s.window == nil { window?.toolbar?.isVisible = true }
        window?.makeFirstResponder(s)
    }

    // MARK: toolbar

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.extractTo, .extractHere, .preview, .open, .add, .delete, .test, .info, .flexibleSpace, .search]
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar) + [.space]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if id == .search {
            let s = NSSearchToolbarItem(itemIdentifier: id)
            s.searchField.target = self; s.searchField.action = #selector(searchChanged(_:))
            s.searchField.sendsSearchStringImmediately = true
            s.searchField.placeholderString = String(localized: "Search in Archive")
            s.label = String(localized: "Search")
            searchField = s.searchField
            return s
        }
        let spec: [NSToolbarItem.Identifier: (String, String, Selector, String)] = [
            .extractTo: (String(localized: "Extract To…"), "arrow.down.doc", #selector(extractTo(_:)), String(localized: "Extract the selection (or everything) to a folder you choose")),
            .extractHere: (String(localized: "Extract Here"), "arrow.down.to.line", #selector(extractHere(_:)), String(localized: "Extract beside the archive")),
            .preview: (String(localized: "Preview"), "eye", #selector(previewSelection(_:)), String(localized: "Quick Look (Space)")),
            .open: (String(localized: "Open"), "arrow.up.forward.app", #selector(openSelection(_:)), String(localized: "Open with the default app")),
            .add: (String(localized: "Add"), "plus", #selector(addFiles(_:)), String(localized: "Add files to the archive")),
            .delete: (String(localized: "Delete"), "trash", #selector(deleteSelection(_:)), String(localized: "Delete from the archive")),
            .test: (String(localized: "Test"), "checkmark.seal", #selector(testArchive(_:)), String(localized: "Check the archive for errors")),
            .info: (String(localized: "Info"), "info.circle", #selector(showInfo(_:)), String(localized: "Archive information")),
        ]
        guard let (label, symbol, action, tip) = spec[id] else { return nil }
        let item = NSToolbarItem(itemIdentifier: id)
        item.label = label; item.paletteLabel = label; item.toolTip = tip
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.target = self; item.action = action
        item.isBordered = true
        return item
    }

    func windowWillClose(_ notification: Notification) {
        CacheManager.shared.remove(session: session)
    }

    @objc func appBecameActive() { checkModifiedFiles() }
}

extension ArchiveWindowController: NSToolbarItemValidation, NSMenuItemValidation {
    func validateToolbarItem(_ item: NSToolbarItem) -> Bool { validate(item.action) }
    func validateMenuItem(_ item: NSMenuItem) -> Bool { validate(item.action) }

    private func validate(_ action: Selector?) -> Bool {
        guard doc.root != nil, !busy else { return false }
        let hasSel = !fileList.selectedNodes.isEmpty
        let hasFileSel = fileList.selectedNodes.contains { !$0.isFolder }
        switch action {
        case #selector(addFiles(_:)): updateWritableTooltips(); return doc.isWritable
        case #selector(deleteSelection(_:)): updateWritableTooltips(); return doc.isWritable && hasSel
        case #selector(previewSelection(_:)), #selector(openWith(_:)): return hasFileSel
        case #selector(openSelection(_:)), #selector(copyPath(_:)): return hasSel
        default: return true
        }
    }

    private func updateWritableTooltips() {
        guard let items = window?.toolbar?.items else { return }
        for i in items where i.itemIdentifier == .add || i.itemIdentifier == .delete {
            i.toolTip = doc.isWritable ? (i.itemIdentifier == .add ? String(localized: "Add files to the archive") : String(localized: "Delete from the archive"))
                                       : String(localized: "This format is read-only")
        }
    }
}

extension ArchiveWindowController: SidebarDelegate {
    func sidebarDidSelectFolder(_ node: ArchiveNode) { if node !== currentFolder { navigate(to: node) } }
    func sidebarDidClickDestination(_ item: DestinationItem) { extractToDestination(item, confirm: true, paths: nil) }
    func sidebarDidDropRows(_ paths: [String], on item: DestinationItem) { extractToDestination(item, confirm: false, paths: paths) }
    func sidebarAddFavorite() {
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.allowsMultipleSelection = true
        p.prompt = String(localized: "Add")
        p.beginSheetModal(for: window!) { r in if r == .OK { p.urls.forEach { self.sidebar.favorites.add($0) } } }
    }
}

extension ArchiveWindowController: FileListDelegate {
    func fileListOpen(_ node: ArchiveNode) { node.isFolder ? navigate(to: node) : openNodes([node]) }
    func fileListSelectionChanged() { updateStatus(); window?.toolbar?.validateVisibleItems(); refreshQuickLook() }
    func fileListPreview() { previewSelection(nil) }
    var fileListAcceptsDrops: Bool { doc.isWritable && !busy }
    func fileListContextMenu() -> NSMenu? { contextMenu() }
}
