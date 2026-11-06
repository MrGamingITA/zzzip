import XCTest
@testable import Zzzip

final class SupportServicesTests: XCTestCase {
    func defaults() -> UserDefaults {
        let name = "zzzip-tests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!; d.removePersistentDomain(forName: name); return d
    }

    func testFavoritesPersistAndDedupe() {
        let d = defaults()
        let a = Fixtures.tempDir(), b = Fixtures.tempDir()
        let f = Favorites(defaults: d)
        f.add(a); f.add(b); f.add(a)
        XCTAssertEqual(f.items.map(\.path), [a.path, b.path])
        f.move(from: 1, to: 0)
        XCTAssertEqual(Favorites(defaults: d).items.map(\.path), [b.path, a.path])
        f.remove(at: 0)
        XCTAssertEqual(Favorites(defaults: d).items.map(\.path), [a.path])
    }

    func testFavoritesDropMissing() {
        let d = defaults()
        let f = Favorites(defaults: d)
        let a = Fixtures.tempDir()
        f.add(a); f.add(URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)"))
        XCTAssertEqual(Favorites(defaults: d).items.map(\.path), [a.path])
    }

    func testBuiltinDestinations() {
        let arc = URL(fileURLWithPath: "/Users/x/Downloads/a.zip")
        XCTAssertEqual(BuiltinDestination.besideArchive.url(archive: arc).path, "/Users/x/Downloads")
        XCTAssertEqual(BuiltinDestination.desktop.url(archive: arc), FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0])
    }

    func testCacheSessionRemoved() throws {
        let root = Fixtures.tempDir()
        let c = CacheManager(root: root)
        let s = c.makeSession()
        try "x".write(to: s.appendingPathComponent("f.txt"), atomically: true, encoding: .utf8)
        c.remove(session: s)
        XCTAssertFalse(FileManager.default.fileExists(atPath: s.path))
        _ = c.makeSession(); _ = c.makeSession()
        c.purgeAll()
        XCTAssertEqual(Fixtures.listing(root), [])
    }

    func testWatcherDetectsChange() throws {
        let f = Fixtures.tempDir().appendingPathComponent("n.txt")
        try "one".write(to: f, atomically: true, encoding: .utf8)
        let w = OpenedFileWatcher()
        w.track(file: f, internalPath: "doc/n.txt")
        XCTAssertTrue(w.modifiedFiles().isEmpty)
        Thread.sleep(forTimeInterval: 1.1)
        try "two!".write(to: f, atomically: true, encoding: .utf8)
        XCTAssertEqual(w.modifiedFiles().map(\.internalPath), ["doc/n.txt"])
        w.markSynced(f)
        XCTAssertTrue(w.modifiedFiles().isEmpty)
    }

    func testSupportedTypesDefaults() {
        func t(_ ext: String) -> SupportedType? { SupportedTypes.all.first { $0.extensions.contains(ext) } }
        XCTAssertEqual(t("dmg")?.isDefaultOn, false)
        XCTAssertEqual(t("iso")?.isDefaultOn, false)
        XCTAssertEqual(t("pkg")?.isDefaultOn, false)
        XCTAssertEqual(t("xar")?.isDefaultOn, false)
        XCTAssertEqual(t("zip")?.isDefaultOn, true)
        XCTAssertEqual(t("rar")?.isDefaultOn, true)
        XCTAssertTrue(SupportedTypes.isArchive(URL(fileURLWithPath: "/a/b.tar.gz")))
        XCTAssertTrue(SupportedTypes.isArchive(URL(fileURLWithPath: "/a/b.7z.001")))
        XCTAssertFalse(SupportedTypes.isArchive(URL(fileURLWithPath: "/a/b.pdf")))
    }

    func testInfoPlistDeclaresAllTypes() throws {
        let info = Bundle.main.infoDictionary!
        let docTypes = info["CFBundleDocumentTypes"] as! [[String: Any]]
        let declared = Set(docTypes.flatMap { ($0["LSItemContentTypes"] as? [String]) ?? [] })
        let imported = (info["UTImportedTypeDeclarations"] as? [[String: Any]]) ?? []
        var importedExts: [String: [String]] = [:]
        for i in imported {
            let tags = i["UTTypeTagSpecification"] as? [String: Any]
            importedExts[i["UTTypeIdentifier"] as! String] = tags?["public.filename-extension"] as? [String]
        }
        for t in SupportedTypes.all {
            XCTAssertTrue(declared.contains(t.identifier), "doc type missing \(t.identifier)")
            if !t.identifier.hasPrefix("public.") && !t.identifier.hasPrefix("com.apple.") {
                XCTAssertEqual(Set(importedExts[t.identifier] ?? []), Set(t.extensions), "imported decl \(t.identifier)")
            }
        }
    }
}
