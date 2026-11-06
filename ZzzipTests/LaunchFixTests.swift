import XCTest
@testable import Zzzip

/// Regression tests for smaller robustness fixes.
final class LaunchFixTests: XCTestCase {
    let engine = SevenZip.bundled
    func e(_ p: String, folder: Bool = false, size: UInt64 = 1) -> ArchiveEntry {
        ArchiveEntry(path: p, isFolder: folder, size: size, packedSize: size, modified: nil, isEncrypted: false, method: nil)
    }

    // the container folder is named after the archive the user sees, not the inner tar.
    func testContainerNamedAfterDisplayedArchive() async throws {
        let a = try Fixtures.make("zip", files: ["one.txt": "1", "two.txt": "2"], name: "tmpXYZ")
        let dest = Fixtures.tempDir()
        let created = try await Extractor(engine: engine).extract(archive: a, items: [], destination: dest, mode: .smart, password: nil,
                                                                  namedAfter: URL(fileURLWithPath: "/x/project-v2.tar.gz")) { _ in
            ConflictAnswer(decision: .skip, applyToAll: true) }
        XCTAssertEqual(created.map(\.lastPathComponent), ["project-v2"])
    }

    // decompressing the inner tar can be cancelled.
    func testInnerTarCancel() async throws {
        let dir = Fixtures.tempDir()
        let big = dir.appendingPathComponent("z.bin")
        FileManager.default.createFile(atPath: big.path, contents: Data(count: 600_000_000))
        let tar = dir.appendingPathComponent("x.tar"); try Fixtures.run7zz(["a", "-ttar", tar.path, big.path])
        try FileManager.default.removeItem(at: big)
        let gz = dir.appendingPathComponent("x.tar.gz"); try Fixtures.run7zz(["a", "-tgzip", "-mx1", gz.path, tar.path])
        try FileManager.default.removeItem(at: tar)
        let info = try await engine.list(gz, password: nil)
        let token = CancelToken()
        Task { try await Task.sleep(nanoseconds: 100_000_000); token.cancel() }
        do { _ = try await InnerTar.resolve(archive: gz, info: info, engine: engine, cacheDir: Fixtures.tempDir(), cancel: token); XCTFail() }
        catch let e as EngineError { XCTAssertEqual(e, .cancelled) }
    }

    // a folder selected together with something inside it is extracted once.
    func testRemovingDescendants() {
        let root = ArchiveTree.build([e("d/a.txt"), e("d/s/b.txt"), e("c.txt")])
        let picked = [root.node(atPath: "d/s/b.txt")!, root.node(atPath: "d")!, root.node(atPath: "c.txt")!]
        XCTAssertEqual(ArchiveNode.removingDescendants(picked).map(\.path), ["d", "c.txt"])
    }

    // "./"-prefixed archives can't be written correctly by 7zz → read-only.
    func testDotPrefixedTarIsReadOnly() {
        let dot = ArchiveInfo(type: "tar", physicalSize: nil, isMultiVolume: false, volumeCount: nil, hasEncryptedEntries: false,
                              entries: [e(".", folder: true), e("./a.txt")])
        let plain = ArchiveInfo(type: "tar", physicalSize: nil, isMultiVolume: false, volumeCount: nil, hasEncryptedEntries: false, entries: [e("a.txt")])
        XCTAssertFalse(FormatCapabilities.isWritable(info: dot, url: URL(fileURLWithPath: "/x.tar")))
        XCTAssertTrue(FormatCapabilities.isWritable(info: plain, url: URL(fileURLWithPath: "/x.tar")))
    }

    // the same rule decides "archive or not" everywhere (Dock drop, Open panel, Finder).
    func testOpenableArchivesIncludeZipBasedFormats() {
        for ext in ["jar", "apk", "epub", "zip", "rar", "tgz"] { XCTAssertTrue(SupportedTypes.isArchive(URL(fileURLWithPath: "/a/b.\(ext)")), ext) }
        XCTAssertFalse(SupportedTypes.isArchive(URL(fileURLWithPath: "/a/b.pdf")))
        XCTAssertFalse(SupportedTypes.isArchive(URL(fileURLWithPath: "/a/b.docx")))
    }

    // file count is computed once with the tree.
    func testFileCountCached() {
        let root = ArchiveTree.build([e("d/a"), e("d/s/b"), e("c"), e("e", folder: true)])
        XCTAssertEqual(root.fileCount, 3)
        XCTAssertEqual(root.node(atPath: "d")?.fileCount, 2)
    }

    // drag-out extractions run one at a time.
    func testSerialRunnerRunsOneAtATime() async throws {
        let runner = SerialRunner()
        let active = Locked(0), maxActive = Locked(0)
        try await withThrowingTaskGroup(of: Void.self) { g in
            for _ in 0..<5 {
                g.addTask {
                    try await runner.run {
                        active.mutate { $0 += 1 }; maxActive.mutate { $0 = max($0, active.value) }
                        try await Task.sleep(nanoseconds: 20_000_000)
                        active.mutate { $0 -= 1 }
                    }
                }
            }
            try await g.waitForAll()
        }
        XCTAssertEqual(maxActive.value, 1)
    }

    // The welcome / create windows show the real app icon from the asset catalog.
    func testAppIconComesFromAssetCatalog() {
        let img = NSImage(named: "AppIcon")
        XCTAssertNotNil(img)
        XCTAssertGreaterThanOrEqual(img?.representations.map(\.pixelsWide).max() ?? 0, 512)
    }
}
