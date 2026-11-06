import AppKit

enum MainMenu {
    static func build() -> NSMenu {
        let main = NSMenu()

        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: String(localized: "About Zzzip"), action: #selector(AppDelegate.showAbout(_:)), keyEquivalent: "")
        let upd = appMenu.addItem(withTitle: String(localized: "Check for Updates…"), action: #selector(AppUpdater.checkForUpdates(_:)), keyEquivalent: "")
        upd.target = AppUpdater.shared
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: String(localized: "Settings…"), action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: ",")
        appMenu.addItem(.separator())
        let services = NSMenuItem(title: String(localized: "Services"), action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(); services.submenu = servicesMenu; NSApp.servicesMenu = servicesMenu
        appMenu.addItem(services)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: String(localized: "Hide Zzzip"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: String(localized: "Hide Others"), action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: String(localized: "Show All"), action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: String(localized: "Quit Zzzip"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let fileItem = NSMenuItem(); main.addItem(fileItem)
        let fileMenu = NSMenu(title: String(localized: "File"))
        fileMenu.addItem(withTitle: String(localized: "New Archive…"), action: #selector(AppDelegate.newArchive(_:)), keyEquivalent: "n")
        fileMenu.addItem(withTitle: String(localized: "Open…"), action: #selector(NSDocumentController.openDocument(_:)), keyEquivalent: "o")
        let recent = NSMenuItem(title: String(localized: "Open Recent"), action: nil, keyEquivalent: "")
        let recentMenu = NSMenu(title: String(localized: "Open Recent"))
        recentMenu.addItem(withTitle: String(localized: "Clear Menu"), action: #selector(NSDocumentController.clearRecentDocuments(_:)), keyEquivalent: "")
        recent.submenu = recentMenu
        recentMenu.perform(NSSelectorFromString("_setMenuName:"), with: "NSRecentDocumentsMenu")
        fileMenu.addItem(recent)
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: String(localized: "Close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = fileMenu

        let editItem = NSMenuItem(); main.addItem(editItem)
        let editMenu = NSMenu(title: String(localized: "Edit"))
        editMenu.addItem(withTitle: String(localized: "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: String(localized: "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: String(localized: "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: String(localized: "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        let arcItem = NSMenuItem(); main.addItem(arcItem)
        let arc = NSMenu(title: String(localized: "Archive"))
        func add(_ t: String, _ sel: Selector, _ key: String = "", _ mods: NSEvent.ModifierFlags = .command) {
            let i = arc.addItem(withTitle: t, action: sel, keyEquivalent: key); i.keyEquivalentModifierMask = mods
        }
        add(String(localized: "Extract To…"), #selector(ArchiveWindowController.extractTo(_:)), "e", [.command, .shift])
        add(String(localized: "Extract Here"), #selector(ArchiveWindowController.extractHere(_:)), "e")
        arc.addItem(.separator())
        add(String(localized: "Open"), #selector(ArchiveWindowController.openSelection(_:)), "\u{2193}")
        add(String(localized: "Open With…"), #selector(ArchiveWindowController.openWith(_:)))
        add(String(localized: "Preview"), #selector(ArchiveWindowController.previewSelection(_:)), "y")
        add(String(localized: "Enclosing Folder"), #selector(ArchiveWindowController.goUp(_:)), "\u{2191}")
        arc.addItem(.separator())
        add(String(localized: "Add Files…"), #selector(ArchiveWindowController.addFiles(_:)), "a", [.command, .shift])
        add(String(localized: "Delete"), #selector(ArchiveWindowController.deleteSelection(_:)), "\u{8}")
        arc.addItem(.separator())
        add(String(localized: "Test"), #selector(ArchiveWindowController.testArchive(_:)), "t")
        add(String(localized: "Info"), #selector(ArchiveWindowController.showInfo(_:)), "i")
        add(String(localized: "Search in Archive"), #selector(ArchiveWindowController.focusSearch(_:)), "f")
        add(String(localized: "Copy Path"), #selector(ArchiveWindowController.copyPath(_:)), "c", [.command, .option])
        arcItem.submenu = arc

        let windowItem = NSMenuItem(); main.addItem(windowItem)
        let windowMenu = NSMenu(title: String(localized: "Window"))
        windowMenu.addItem(withTitle: String(localized: "Minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: String(localized: "Zoom"), action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu

        let helpItem = NSMenuItem(); main.addItem(helpItem)
        let helpMenu = NSMenu(title: String(localized: "Help"))
        helpItem.submenu = helpMenu
        NSApp.helpMenu = helpMenu
        return main
    }
}
