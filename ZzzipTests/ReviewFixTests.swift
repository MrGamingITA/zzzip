import XCTest
@testable import Zzzip

/// Regression tests for data-safety and robustness fixes.
final class ReviewFixTests: XCTestCase {
    let engine = SevenZip.bundled

    // "._*" must be excluded, also nested.
    func testExcludesAppleDoubleFilesNested() async throws {
        let base = Fixtures.tempDir().appendingPathComponent("Proj/sub")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try "a".write(to: base.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "x".write(to: base.appendingPathComponent("._a.txt"), atomically: true, encoding: .utf8)
        for f in [CreateFormat.zip, .sevenZip, .tar] {
            let r = try await ArchiveCreator(engine: engine).create(sources: [base.deletingLastPathComponent()],
                                                                    options: CreateOptions(name: "O", destination: Fixtures.tempDir(), format: f))
            let paths = try await engine.list(r, password: nil).entries.map(\.path)
            XCTAssertTrue(paths.contains("Proj/sub/a.txt"), "\(f)")
            XCTAssertFalse(paths.contains { $0.hasSuffix("._a.txt") }, "\(f): \(paths)")
        }
    }

    // sources from different folders are all archived.
    func testCreateFromDifferentFolders() async throws {
        let d1 = Fixtures.tempDir(), d2 = Fixtures.tempDir()
        let a = d1.appendingPathComponent("a.txt"), b = d2.appendingPathComponent("b.txt")
        try "a".write(to: a, atomically: true, encoding: .utf8); try "b".write(to: b, atomically: true, encoding: .utf8)
        for f in [CreateFormat.zip, .tarGz] {
            let r = try await ArchiveCreator(engine: engine).create(sources: [a, b], options: CreateOptions(name: "M", destination: Fixtures.tempDir(), format: f))
            var info = try await engine.list(r, password: nil)
            if f == .tarGz {
                let inner = try await InnerTar.resolve(archive: r, info: info, engine: engine, cacheDir: Fixtures.tempDir())!
                info = try await engine.list(inner, password: nil)
            }
            XCTAssertEqual(Set(info.entries.map(\.path)), ["a.txt", "b.txt"], "\(f)")
        }
    }

    // a missing/unreadable source is an error, not a silent success.
    func testCreateWarningIsFailure() async throws {
        let d = Fixtures.tempDir()
        let a = d.appendingPathComponent("a.txt"); try "a".write(to: a, atomically: true, encoding: .utf8)
        let missing = d.appendingPathComponent("gone.txt")
        let dest = Fixtures.tempDir()
        do {
            _ = try await ArchiveCreator(engine: engine).create(sources: [a, missing], options: CreateOptions(name: "W", destination: dest))
            XCTFail("should fail")
        } catch {}
        XCTAssertEqual(Fixtures.listing(dest), [])
    }

    // deleting something 7zz can't delete must throw, not silently do nothing.
    func testDeleteThatChangesNothingThrows() async throws {
        let dir = Fixtures.tempDir()
        let src = dir.appendingPathComponent("t"); try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try "k".write(to: src.appendingPathComponent("keep.txt"), atomically: true, encoding: .utf8)
        let tar = dir.appendingPathComponent("dot.tar")
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/tar"); p.arguments = ["-cf", tar.path, "."]; p.currentDirectoryURL = src
        try p.run(); p.waitUntilExit()
        let info = try await engine.list(tar, password: nil)
        let node = ArchiveTree.build(info.entries).node(atPath: "keep.txt")!
        do { try await ArchiveEditor(engine: engine).delete(paths: [node.archivePath], archive: tar, password: nil); XCTFail("should throw") }
        catch {}
        let after = try await engine.list(tar, password: nil)
        XCTAssertTrue(after.entries.contains { $0.path.hasSuffix("keep.txt") })
    }

    // extracting requested items that 7zz didn't produce must throw.
    func testExtractNothingProducedThrows() async throws {
        let a = try Fixtures.make("zip", files: ["a.txt": "a"])
        let ghost = ArchiveNode(name: "ghost.txt", path: "ghost.txt", isFolder: false)
        do {
            _ = try await Extractor(engine: engine).extract(archive: a, items: [ghost], destination: Fixtures.tempDir(), mode: .smart, password: nil) { _ in
                ConflictAnswer(decision: .skip, applyToAll: true) }
            XCTFail("should throw")
        } catch {}
    }

    // adding to an archive with encrypted entries without a known password must ask first.
    func testNeedsPasswordBeforeAdding() {
        let enc = ArchiveInfo(type: "zip", physicalSize: nil, isMultiVolume: false, volumeCount: nil, hasEncryptedEntries: true, entries: [])
        let plain = ArchiveInfo(type: "zip", physicalSize: nil, isMultiVolume: false, volumeCount: nil, hasEncryptedEntries: false, entries: [])
        XCTAssertTrue(FormatCapabilities.needsPasswordBeforeWriting(info: enc, password: nil))
        XCTAssertFalse(FormatCapabilities.needsPasswordBeforeWriting(info: enc, password: "pw"))
        XCTAssertFalse(FormatCapabilities.needsPasswordBeforeWriting(info: plain, password: nil))
    }

    // busy state is a counter, not a Bool.
    func testBusyCounter() {
        let b = BusyCounter()
        XCTAssertFalse(b.isBusy)
        b.begin(); b.begin(); b.end()
        XCTAssertTrue(b.isBusy)
        b.end()
        XCTAssertFalse(b.isBusy)
    }

    // a question asked during an operation goes on top of the progress sheet, not behind it.
    func testSheetHostPrefersAttachedSheet() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        XCTAssertTrue(SheetHost.host(for: w) === w)
        let s = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 50), styleMask: [.titled], backing: .buffered, defer: false)
        w.beginSheet(s, completionHandler: nil)
        XCTAssertTrue(SheetHost.host(for: w) === s)
        XCTAssertTrue(SheetHost.clear(w) === w)
        XCTAssertNil(w.attachedSheet)
    }
}
