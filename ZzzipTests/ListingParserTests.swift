import XCTest
@testable import Zzzip

enum ListingFixtures {
    static func entry(_ path: String, folder: Bool = false, size: Int = 0, packed: Int = 0, encrypted: Bool = false) -> String {
        """
        Path = \(path)
        Folder = \(folder ? "+" : "-")
        Size = \(size)
        Packed Size = \(packed)
        Modified = 2026-11-03 14:39:02.4613325
        Attributes = \(folder ? "D drwxr-xr-x" : " -rw-r--r--")
        Encrypted = \(encrypted ? "+" : "-")
        Method = Deflate

        """
    }
    static func listing(type: String = "zip", extraProps: String = "", entries: [String]) -> String {
        """
        7-Zip (z) 26.05 (arm64) : Copyright (c) 1999-2026 Igor Pavlov : 2026-10-21

        Scanning the drive for archives:
        1 file, 401 bytes (1 KiB)

        Listing archive: /tmp/t.\(type)

        --
        Path = /tmp/t.\(type)
        Type = \(type)
        Physical Size = 401
        \(extraProps)
        ----------
        \(entries.joined(separator: "\n"))
        """
    }
}

final class ListingParserTests: XCTestCase {
    func testParsesZipListing() throws {
        let out = ListingFixtures.listing(entries: [
            ListingFixtures.entry("doc", folder: true),
            ListingFixtures.entry("doc/a.txt", size: 4, packed: 1),
            ListingFixtures.entry("b.pdf", size: 10, packed: 9),
        ])
        let info = try ListingParser.parse(out)
        XCTAssertEqual(info.type, "zip")
        XCTAssertEqual(info.physicalSize, 401)
        XCTAssertEqual(info.entries.count, 3)
        XCTAssertTrue(info.entries[0].isFolder)
        XCTAssertEqual(info.entries[1].path, "doc/a.txt")
        XCTAssertEqual(info.entries[1].size, 4)
        XCTAssertEqual(info.entries[1].packedSize, 1)
        XCTAssertEqual(info.entries[1].method, "Deflate")
        XCTAssertNotNil(info.entries[1].modified)
        XCTAssertFalse(info.hasEncryptedEntries)
    }

    func testParsesEncryptedFlag() throws {
        let info = try ListingParser.parse(ListingFixtures.listing(entries: [ListingFixtures.entry("a.txt", encrypted: true)]))
        XCTAssertTrue(info.entries[0].isEncrypted)
        XCTAssertTrue(info.hasEncryptedEntries)
    }

    func testParsesMultivolume() throws {
        let info = try ListingParser.parse(ListingFixtures.listing(type: "7z", extraProps: "Multivolume = +\nVolumes = 3", entries: [ListingFixtures.entry("a.txt")]))
        XCTAssertTrue(info.isMultiVolume)
        XCTAssertEqual(info.volumeCount, 3)
    }

    func testNamelessEntryGetsNameFromArchive() throws {
        let out = ListingFixtures.listing(type: "xz", entries: ["Size = 2560\nPacked Size = 156\nMethod = LZMA2:12 CRC32\n"])
        XCTAssertEqual(try ListingParser.parse(out, archiveName: "x.tar.xz").entries.map(\.path), ["x.tar"])
        XCTAssertEqual(try ListingParser.parse(out, archiveName: "y.txz").entries.map(\.path), ["y.tar"])
        XCTAssertEqual(try ListingParser.parse(out, archiveName: "notes.txt.bz2").entries.map(\.path), ["notes.txt"])
    }

    func testRejectsOutputWithoutListing() {
        XCTAssertThrowsError(try ListingParser.parse("garbage"))
    }

    func testLargeListingPerformance() throws {
        var entries: [String] = []
        entries.reserveCapacity(20_000)
        for i in 0..<20_000 { entries.append(ListingFixtures.entry("folder\(i % 200)/sub/file\(i).txt", size: i, packed: i / 2)) }
        let out = ListingFixtures.listing(entries: entries)
        let start = Date()
        let info = try ListingParser.parse(out)
        let root = ArchiveTree.build(info.entries)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(info.entries.count, 20_000)
        XCTAssertEqual(root.children.count, 200)
        XCTAssertLessThan(elapsed, 1.0)
    }
}
