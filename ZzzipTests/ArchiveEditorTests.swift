import XCTest
import CryptoKit
@testable import Zzzip

final class ArchiveEditorTests: XCTestCase {
    let engine = SevenZip.bundled
    lazy var editor = ArchiveEditor(engine: engine)

    func paths(_ a: URL, pw: String? = nil) async throws -> Set<String> {
        Set(try await engine.list(a, password: pw).entries.filter { !$0.isFolder }.map(\.path))
    }
    func file(_ name: String, _ content: String) throws -> URL {
        let u = Fixtures.tempDir().appendingPathComponent(name)
        try content.write(to: u, atomically: true, encoding: .utf8); return u
    }
    func sha(_ u: URL) throws -> String { SHA256.hash(data: try Data(contentsOf: u)).description }
    func noTemp(_ a: URL) -> Bool {
        !((try? FileManager.default.contentsOfDirectory(atPath: a.deletingLastPathComponent().path)) ?? []).contains { $0.contains(".zzzip-") }
    }

    func testAddToRoot() async throws {
        let a = try Fixtures.make("zip", files: ["a.txt": "a"])
        try await editor.add(files: [try file("new.txt", "n")], intoFolder: "", archive: a, password: nil)
        let p = try await paths(a)
        XCTAssertEqual(p, ["a.txt", "new.txt"])
        XCTAssertTrue(noTemp(a))
    }

    func testAddIntoSubfolder() async throws {
        let a = try Fixtures.make("7z", files: ["doc/a.txt": "a"])
        try await editor.add(files: [try file("new.txt", "n")], intoFolder: "doc", archive: a, password: nil)
        let p = try await paths(a)
        XCTAssertEqual(p, ["doc/a.txt", "doc/new.txt"])
    }

    func testAddFolder() async throws {
        let a = try Fixtures.make("zip", files: ["a.txt": "a"])
        let dir = Fixtures.tempDir().appendingPathComponent("pics")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "p".write(to: dir.appendingPathComponent("p.png"), atomically: true, encoding: .utf8)
        try await editor.add(files: [dir], intoFolder: "", archive: a, password: nil)
        let p = try await paths(a)
        XCTAssertEqual(p, ["a.txt", "pics/p.png"])
    }

    func testAddWithPasswordEncrypts() async throws {
        let a = try Fixtures.make("7z", files: ["a.txt": "a"], password: "pw", encryptHeaders: true)
        try await editor.add(files: [try file("new.txt", "n")], intoFolder: "", archive: a, password: "pw", encryptHeaders: true)
        do { _ = try await engine.list(a, password: nil); XCTFail() } catch let e as EngineError { XCTAssertEqual(e, .passwordRequired) }
        let p = try await paths(a, pw: "pw")
        XCTAssertEqual(p, ["a.txt", "new.txt"])
    }

    func testDeleteFile() async throws {
        let a = try Fixtures.make("zip", files: ["a.txt": "a", "b.txt": "b"])
        try await editor.delete(paths: ["a.txt"], archive: a, password: nil)
        let p = try await paths(a)
        XCTAssertEqual(p, ["b.txt"])
    }

    func testDeleteFolder() async throws {
        let a = try Fixtures.make("zip", files: ["doc/a.txt": "a", "doc/sub/b.txt": "b", "c.txt": "c"])
        try await editor.delete(paths: ["doc"], archive: a, password: nil)
        let all = Set(try await engine.list(a, password: nil).entries.map(\.path))
        XCTAssertEqual(all, ["c.txt"])
    }

    func testUpdateReplacesContent() async throws {
        let a = try Fixtures.make("zip", files: ["doc/n.txt": "old", "x.txt": "x"])
        let edited = try file("n.txt", "new content")
        try await editor.update(file: edited, internalPath: "doc/n.txt", archive: a, password: nil)
        let out = Fixtures.tempDir()
        try await engine.extract(a, items: ["doc/n.txt"], to: out, password: nil)
        XCTAssertEqual(try String(contentsOf: out.appendingPathComponent("doc/n.txt"), encoding: .utf8), "new content")
        let p = try await paths(a)
        XCTAssertEqual(p, ["doc/n.txt", "x.txt"])
    }

    func testCancelKeepsOriginal() async throws {
        let dir = Fixtures.tempDir()
        let a = try Fixtures.make("7z", files: ["a.txt": "a"], in: dir)
        let before = try sha(a)
        let big = dir.appendingPathComponent("big.bin")
        FileManager.default.createFile(atPath: big.path, contents: Data((0..<60_000_000).map { _ in UInt8.random(in: 0...255) }))
        let token = CancelToken()
        Task { try await Task.sleep(nanoseconds: 150_000_000); token.cancel() }
        do { try await editor.add(files: [big], intoFolder: "", archive: a, password: nil, cancel: token); XCTFail() }
        catch let e as EngineError { XCTAssertEqual(e, .cancelled) }
        XCTAssertEqual(try sha(a), before)
        XCTAssertTrue(noTemp(a))
    }

    func testFailureKeepsOriginal() async throws {
        let a = try Fixtures.make("zip", files: ["a.txt": "a"])
        let before = try sha(a)
        let missing = Fixtures.tempDir().appendingPathComponent("does-not-exist.txt")
        do { try await editor.add(files: [missing], intoFolder: "", archive: a, password: nil); XCTFail() } catch {}
        XCTAssertEqual(try sha(a), before)
        XCTAssertTrue(noTemp(a))
    }

    func testWritability() {
        func info(_ t: String, multi: Bool = false) -> ArchiveInfo {
            ArchiveInfo(type: t, physicalSize: nil, isMultiVolume: multi, volumeCount: nil, hasEncryptedEntries: false, entries: [])
        }
        XCTAssertTrue(FormatCapabilities.isWritable(info: info("zip"), url: URL(fileURLWithPath: "/x.zip")))
        XCTAssertTrue(FormatCapabilities.isWritable(info: info("7z"), url: URL(fileURLWithPath: "/x.7z")))
        XCTAssertTrue(FormatCapabilities.isWritable(info: info("tar"), url: URL(fileURLWithPath: "/x.tar")))
        XCTAssertFalse(FormatCapabilities.isWritable(info: info("gzip"), url: URL(fileURLWithPath: "/x.tar.gz")))
        XCTAssertFalse(FormatCapabilities.isWritable(info: info("tar"), url: URL(fileURLWithPath: "/x.tgz")))
        XCTAssertFalse(FormatCapabilities.isWritable(info: info("Rar5"), url: URL(fileURLWithPath: "/x.rar")))
        XCTAssertFalse(FormatCapabilities.isWritable(info: info("7z", multi: true), url: URL(fileURLWithPath: "/x.7z.001")))
    }
}
