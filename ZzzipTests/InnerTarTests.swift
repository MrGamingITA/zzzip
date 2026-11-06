import XCTest
@testable import Zzzip

final class InnerTarTests: XCTestCase {
    let engine = SevenZip.bundled

    func makeTarGz(_ ext: String, compressor: String) throws -> URL {
        let dir = Fixtures.tempDir()
        let src = dir.appendingPathComponent("src/docs")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try "a".write(to: src.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let tar = dir.appendingPathComponent("x.tar")
        try Fixtures.run7zz(["a", "-ttar", tar.path, "docs"], cwd: dir.appendingPathComponent("src"))
        let out = dir.appendingPathComponent("x.\(ext)")
        try Fixtures.run7zz(["a", "-t\(compressor)", out.path, tar.path])
        try FileManager.default.removeItem(at: tar)
        return out
    }

    func testTarGzResolvesToInnerTar() async throws {
        for (ext, comp) in [("tar.gz", "gzip"), ("tgz", "gzip"), ("tar.xz", "xz"), ("tar.bz2", "bzip2")] {
            let a = try makeTarGz(ext, compressor: comp)
            let outer = try await engine.list(a, password: nil)
            let cache = Fixtures.tempDir()
            let inner = try await InnerTar.resolve(archive: a, info: outer, engine: engine, cacheDir: cache)
            XCTAssertNotNil(inner, "\(ext) type=\(outer.type) entries=\(outer.entries.map(\.path))")
            guard inner != nil else { continue }
            let info = try await engine.list(inner!, password: nil)
            XCTAssertEqual(info.type, "tar", ext)
            XCTAssertTrue(info.entries.map(\.path).contains("docs/a.txt"), ext)
        }
    }

    func testPlainGzipIsNotResolved() async throws {
        let dir = Fixtures.tempDir()
        let f = dir.appendingPathComponent("notes.txt")
        try "hello".write(to: f, atomically: true, encoding: .utf8)
        let gz = dir.appendingPathComponent("notes.txt.gz")
        try Fixtures.run7zz(["a", "-tgzip", gz.path, f.path])
        let info = try await engine.list(gz, password: nil)
        let r = try await InnerTar.resolve(archive: gz, info: info, engine: engine, cacheDir: Fixtures.tempDir())
        XCTAssertNil(r)
    }

    func testZipIsNotResolved() async throws {
        let a = try Fixtures.make("zip", files: ["a.tar": "x"])
        let info = try await engine.list(a, password: nil)
        let r = try await InnerTar.resolve(archive: a, info: info, engine: engine, cacheDir: Fixtures.tempDir())
        XCTAssertNil(r)
    }
}
