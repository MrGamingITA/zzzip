import XCTest
@testable import Zzzip

final class ExtractorTests: XCTestCase {
    let engine = SevenZip.bundled
    lazy var extractor = Extractor(engine: engine)

    func tree(_ a: URL, password: String? = nil) async throws -> ArchiveNode {
        ArchiveTree.build(try await engine.list(a, password: password).entries)
    }
    func never(_ u: URL) async -> ConflictAnswer { XCTFail("unexpected conflict \(u)"); return ConflictAnswer(decision: .skip, applyToAll: false) }

    func testExtractAllSmart() async throws {
        let a = try Fixtures.make("zip", files: ["one.txt": "1", "two/b.txt": "2"], name: "Progetto")
        let dest = Fixtures.tempDir()
        let created = try await extractor.extract(archive: a, items: [], destination: dest, mode: .smart, password: nil, onConflict: never)
        XCTAssertEqual(created.map(\.path), [dest.appendingPathComponent("Progetto").path])
        XCTAssertEqual(Fixtures.listing(dest), ["Progetto", "Progetto/one.txt", "Progetto/two", "Progetto/two/b.txt"])
    }

    func testExtractSingleTopLevelLoose() async throws {
        let a = try Fixtures.make("zip", files: ["only/a.txt": "1"], name: "P")
        let dest = Fixtures.tempDir()
        _ = try await extractor.extract(archive: a, items: [], destination: dest, mode: .smart, password: nil, onConflict: never)
        XCTAssertEqual(Fixtures.listing(dest), ["only", "only/a.txt"])
    }

    func testExtractSubfolderItemKeepsRelative() async throws {
        let a = try Fixtures.make("zip", files: ["doc/img/p.png": "p", "doc/n.txt": "n"])
        let root = try await tree(a)
        let dest = Fixtures.tempDir()
        _ = try await extractor.extract(archive: a, items: [root.node(atPath: "doc/img")!], destination: dest, mode: .smart, password: nil, onConflict: never)
        XCTAssertEqual(Fixtures.listing(dest), ["img", "img/p.png"])
    }

    func testExtractTwoSelectedItemsMakesFolder() async throws {
        let a = try Fixtures.make("zip", files: ["doc/img/p.png": "p", "doc/n.txt": "n", "z.txt": "z"], name: "Arc")
        let root = try await tree(a)
        let dest = Fixtures.tempDir()
        _ = try await extractor.extract(archive: a, items: [root.node(atPath: "doc/img")!, root.node(atPath: "doc/n.txt")!],
                                        destination: dest, mode: .smart, password: nil, onConflict: never)
        XCTAssertEqual(Fixtures.listing(dest), ["Arc", "Arc/img", "Arc/img/p.png", "Arc/n.txt"])
    }

    func testConflictKeepBoth() async throws {
        let a = try Fixtures.make("zip", files: ["a.txt": "new"])
        let dest = Fixtures.tempDir()
        try "old".write(to: dest.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        _ = try await extractor.extract(archive: a, items: [], destination: dest, mode: .smart, password: nil) { _ in ConflictAnswer(decision: .keepBoth, applyToAll: false) }
        XCTAssertEqual(Fixtures.listing(dest), ["a 2.txt", "a.txt"])
        XCTAssertEqual(try String(contentsOf: dest.appendingPathComponent("a.txt"), encoding: .utf8), "old")
    }

    func testConflictSkip() async throws {
        let a = try Fixtures.make("zip", files: ["a.txt": "new"])
        let dest = Fixtures.tempDir()
        try "old".write(to: dest.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        _ = try await extractor.extract(archive: a, items: [], destination: dest, mode: .loose, password: nil) { _ in ConflictAnswer(decision: .skip, applyToAll: false) }
        XCTAssertEqual(try String(contentsOf: dest.appendingPathComponent("a.txt"), encoding: .utf8), "old")
        XCTAssertEqual(Fixtures.listing(dest), ["a.txt"])
    }

    func testConflictReplaceApplyToAll() async throws {
        let a = try Fixtures.make("zip", files: ["a.txt": "n", "b.txt": "n", "c.txt": "n"])
        let dest = Fixtures.tempDir()
        for n in ["a.txt", "b.txt", "c.txt"] { try "old".write(to: dest.appendingPathComponent(n), atomically: true, encoding: .utf8) }
        let calls = Locked(0)
        _ = try await extractor.extract(archive: a, items: [], destination: dest, mode: .loose, password: nil) { _ in
            calls.mutate { $0 += 1 }; return ConflictAnswer(decision: .replace, applyToAll: true)
        }
        XCTAssertEqual(calls.value, 1)
        for n in ["a.txt", "b.txt", "c.txt"] { XCTAssertEqual(try String(contentsOf: dest.appendingPathComponent(n), encoding: .utf8), "n") }
    }

    func testStagingRemovedOnError() async throws {
        let a = try Fixtures.make("7z", files: ["a.txt": "s", "b.txt": "t"], password: "pw")
        let dest = Fixtures.tempDir()
        do { _ = try await extractor.extract(archive: a, items: [], destination: dest, mode: .smart, password: "bad", onConflict: never); XCTFail() }
        catch let e as EngineError { XCTAssertEqual(e, .wrongPassword) }
        XCTAssertEqual(Fixtures.listing(dest), [])
    }

    func testCancelLeavesNothing() async throws {
        let dir = Fixtures.tempDir()
        let big = dir.appendingPathComponent("zeros.bin")
        FileManager.default.createFile(atPath: big.path, contents: Data(count: 800_000_000))
        let a = dir.appendingPathComponent("z.7z")
        try Fixtures.run7zz(["a", "-mx1", a.path, big.path])
        try FileManager.default.removeItem(at: big)
        let dest = Fixtures.tempDir()
        try "keep".write(to: dest.appendingPathComponent("existing.txt"), atomically: true, encoding: .utf8)
        let token = CancelToken()
        Task { try await Task.sleep(nanoseconds: 100_000_000); token.cancel() }
        do { _ = try await extractor.extract(archive: a, items: [], destination: dest, mode: .smart, password: nil, onConflict: never, cancel: token); XCTFail() }
        catch let e as EngineError { XCTAssertEqual(e, .cancelled) }
        XCTAssertEqual(Fixtures.listing(dest), ["existing.txt"])
    }

    func testZipSlipStaysInside() async throws {
        let dir = Fixtures.tempDir()
        let dest = dir.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let a = dir.appendingPathComponent("evil.zip")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        p.arguments = ["-I", "-c", "import zipfile,sys; z=zipfile.ZipFile(sys.argv[1],'w'); z.writestr('../evil.txt','x'); z.writestr('/abs.txt','y'); z.writestr('ok.txt','z'); z.close()", a.path]
        try p.run(); p.waitUntilExit()
        _ = try? await extractor.extract(archive: a, items: [], destination: dest, mode: .loose, password: nil) { _ in ConflictAnswer(decision: .skip, applyToAll: true) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("evil.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: "/abs.txt"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.appendingPathComponent("ok.txt").path))
        XCTAssertFalse(Fixtures.listing(dest).contains { $0.hasPrefix(".zzzip-staging") })
    }
}
