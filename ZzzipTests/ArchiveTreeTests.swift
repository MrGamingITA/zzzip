import XCTest
@testable import Zzzip

final class ArchiveTreeTests: XCTestCase {
    private func e(_ p: String, folder: Bool = false, size: UInt64 = 0, packed: UInt64 = 0) -> ArchiveEntry {
        ArchiveEntry(path: p, isFolder: folder, size: size, packedSize: packed, modified: nil, isEncrypted: false, method: nil)
    }

    func testImplicitFolders() {
        let root = ArchiveTree.build([e("a/b/c.txt", size: 3)])
        XCTAssertEqual(root.path, "")
        XCTAssertEqual(root.children.count, 1)
        XCTAssertEqual(root.node(atPath: "a/b")?.isFolder, true)
        XCTAssertNil(root.node(atPath: "a/b")?.entry)
        XCTAssertEqual(root.node(atPath: "a/b/c.txt")?.parent?.path, "a/b")
    }

    func testExplicitFolderMergedWithImplicit() {
        let root = ArchiveTree.build([e("a/x.txt"), e("a", folder: true)])
        XCTAssertEqual(root.children.count, 1)
        XCTAssertNotNil(root.node(atPath: "a")?.entry)
    }

    func testTotals() {
        let root = ArchiveTree.build([e("d/a", size: 10, packed: 4), e("d/s/b", size: 5, packed: 2), e("c", size: 1, packed: 1)])
        XCTAssertEqual(root.node(atPath: "d")?.totalSize, 15)
        XCTAssertEqual(root.node(atPath: "d")?.totalPacked, 6)
        XCTAssertEqual(root.totalSize, 16)
        XCTAssertEqual(root.node(atPath: "d")?.allDescendantFiles.map(\.path).sorted(), ["d/a", "d/s/b"])
    }

    func testSortFoldersFirst() {
        let root = ArchiveTree.build([e("z", folder: true), e("a.txt"), e("B", folder: true), e("file10"), e("file9")])
        XCTAssertEqual(root.children.map(\.name), ["B", "z", "a.txt", "file9", "file10"])
    }

    func testStripsTrailingSlashAndLeadingDotSlash() {
        let root = ArchiveTree.build([e("./doc/", folder: true), e("doc/a")])
        XCTAssertEqual(root.children.map(\.name), ["doc"])
        XCTAssertEqual(root.node(atPath: "doc/a")?.path, "doc/a")
    }
}
