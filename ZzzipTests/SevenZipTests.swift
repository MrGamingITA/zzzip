import XCTest
@testable import Zzzip

final class SevenZipTests: XCTestCase {
    let engine = SevenZip.bundled

    func testProgressParser() {
        XCTAssertEqual(ProgressParser.lastPercent(in: "  0%\u{8}\u{8}\u{8} 30% + big.bin\u{8}\u{8} 60% + big.bin"), 0.6)
        XCTAssertNil(ProgressParser.lastPercent(in: "no progress"))
        XCTAssertEqual(ProgressParser.lastPercent(in: "100%"), 1.0)
    }

    func testListZip() async throws {
        let a = try Fixtures.make("zip", files: ["doc/a.txt": "ciao", "b.txt": "x"])
        let info = try await engine.list(a, password: nil)
        XCTAssertEqual(info.type, "zip")
        XCTAssertEqual(Set(info.entries.filter { !$0.isFolder }.map(\.path)), ["doc/a.txt", "b.txt"])
    }

    func testListNotArchive() async throws {
        let d = Fixtures.tempDir().appendingPathComponent("n.zip")
        try "not an archive".write(to: d, atomically: true, encoding: .utf8)
        do { _ = try await engine.list(d, password: nil); XCTFail() } catch let e as EngineError { XCTAssertEqual(e, .unsupportedFormat) }
    }

    func testWrongPassword() async throws {
        let a = try Fixtures.make("7z", files: ["a.txt": "secret"], password: "pw")
        let out = Fixtures.tempDir()
        do { try await engine.extract(a, items: [], to: out, password: "bad"); XCTFail() } catch let e as EngineError { XCTAssertEqual(e, .wrongPassword) }
    }

    func testRightPasswordExtracts() async throws {
        let a = try Fixtures.make("7z", files: ["a.txt": "secret"], password: "pw")
        let out = Fixtures.tempDir()
        try await engine.extract(a, items: [], to: out, password: "pw")
        XCTAssertEqual(try String(contentsOf: out.appendingPathComponent("a.txt"), encoding: .utf8), "secret")
    }

    func testEncryptedHeadersNeedPassword() async throws {
        let a = try Fixtures.make("7z", files: ["a.txt": "s"], password: "pw", encryptHeaders: true)
        let start = Date()
        do { _ = try await engine.list(a, password: nil); XCTFail() } catch let e as EngineError { XCTAssertEqual(e, .passwordRequired) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
        let info = try await engine.list(a, password: "pw")
        XCTAssertEqual(info.entries.map(\.path), ["a.txt"])
    }

    func testSpecialNames() async throws {
        let names = ["spazio è 😀.txt", "[x]*.txt", "-dash.txt"]
        let a = try Fixtures.make("zip", files: Dictionary(uniqueKeysWithValues: names.map { ($0, $0) }))
        let info = try await engine.list(a, password: nil)
        XCTAssertEqual(Set(info.entries.map(\.path)), Set(names))
        let out = Fixtures.tempDir()
        try await engine.extract(a, items: ["-dash.txt"], to: out, password: nil)
        XCTAssertEqual(Fixtures.listing(out), ["-dash.txt"])
        let out2 = Fixtures.tempDir()
        try await engine.extract(a, items: ["[x]*.txt"], to: out2, password: nil)
        XCTAssertEqual(Fixtures.listing(out2), ["[x]*.txt"])
    }

    func testTestCommand() async throws {
        let a = try Fixtures.make("zip", files: ["a.txt": "x"])
        try await engine.test(a, password: nil)
    }

    func testProgressReported() async throws {
        let dir = Fixtures.tempDir()
        let big = dir.appendingPathComponent("big.bin")
        FileManager.default.createFile(atPath: big.path, contents: Data((0..<30_000_000).map { _ in UInt8.random(in: 0...255) }))
        let a = dir.appendingPathComponent("big.7z")
        try Fixtures.run7zz(["a", "-mx1", a.path, big.path])
        let values = Locked<[Double]>([])
        try await engine.extract(a, items: [], to: dir.appendingPathComponent("out"), password: nil, progress: { v in values.mutate { $0.append(v) } })
        XCTAssertTrue(values.value.contains { $0 > 0 })
        XCTAssertLessThanOrEqual(values.value.last ?? 0, 1)
    }

    func testCancel() async throws {
        let dir = Fixtures.tempDir()
        let big = dir.appendingPathComponent("zeros.bin")
        FileManager.default.createFile(atPath: big.path, contents: Data(count: 400_000_000))
        let token = CancelToken()
        let a = dir.appendingPathComponent("z.7z")
        Task { try await Task.sleep(nanoseconds: 150_000_000); token.cancel() }
        do {
            _ = try await engine.run(["a", "-mx9", a.path, big.path], cancel: token)
            XCTFail("should have been cancelled")
        } catch let e as EngineError { XCTAssertEqual(e, .cancelled) }
    }
}

