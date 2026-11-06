import XCTest
@testable import Zzzip

final class ArchiveCreatorTests: XCTestCase {
    let out = URL(fileURLWithPath: "/d/A.zip")
    func opts(_ f: CreateFormat = .zip) -> CreateOptions { CreateOptions(name: "A", destination: URL(fileURLWithPath: "/d"), format: f) }

    func testArgumentsZipDefault() {
        let cmds = ArchiveCreator.arguments(output: out, sources: ["a.txt", "dir"], options: opts())
        XCTAssertEqual(cmds, [["a", "-tzip", "/d/A.zip", "-mx5", "-bsp1", "-bb0", "-xr!.DS_Store", "-xr!__MACOSX", "-xr!._*", "--", "a.txt", "dir"]])
    }
    func testArgumentsNoExclusions() {
        var o = opts(); o.excludeMacFiles = false; o.level = .none
        XCTAssertEqual(ArchiveCreator.arguments(output: out, sources: ["a"], options: o), [["a", "-tzip", "/d/A.zip", "-mx0", "-bsp1", "-bb0", "--", "a"]])
    }
    func testArgumentsZipPassword() {
        var o = opts(); o.password = "pw"
        let c = ArchiveCreator.arguments(output: out, sources: ["a"], options: o)[0]
        XCTAssertTrue(c.contains("-ppw")); XCTAssertTrue(c.contains("-mem=AES256")); XCTAssertFalse(c.contains("-mhe=on"))
    }
    func testArguments7zEncryptNames() {
        var o = opts(.sevenZip); o.password = "pw"; o.encryptNames = true
        let c = ArchiveCreator.arguments(output: URL(fileURLWithPath: "/d/A.7z"), sources: ["a"], options: o)[0]
        XCTAssertTrue(c.contains("-t7z")); XCTAssertTrue(c.contains("-ppw")); XCTAssertTrue(c.contains("-mhe=on"))
    }
    func testPasswordIgnoredForTar() {
        var o = opts(.tarGz); o.password = "pw"
        XCTAssertFalse(ArchiveCreator.arguments(output: URL(fileURLWithPath: "/d/A.tar.gz"), sources: ["a"], options: o).joined().contains("-ppw"))
    }
    func testArgumentsTarGzTwoSteps() {
        let cmds = ArchiveCreator.arguments(output: URL(fileURLWithPath: "/d/A.tar.gz"), sources: ["a"], options: opts(.tarGz))
        XCTAssertEqual(cmds, [["a", "-ttar", "-so", "-an", "-xr!.DS_Store", "-xr!__MACOSX", "-xr!._*", "--", "a"],
                              ["a", "-tgzip", "-siA.tar", "-mx5", "/d/A.tar.gz"]])
    }
    func testArgumentsKeepLiteralNamesWithWildcards() {
        XCTAssertTrue(ArchiveCreator.arguments(output: out, sources: ["/x/[a]*.txt"], options: opts())[0].contains("-spd"))
    }
    func testArgumentsVolumes() {
        var o = opts(); o.volumeSize = 100 * 1024 * 1024
        XCTAssertTrue(ArchiveCreator.arguments(output: out, sources: ["a"], options: o)[0].contains("-v104857600b"))
    }
    func testDefaultNameSingle() {
        XCTAssertEqual(ArchiveCreator.defaultName(for: [URL(fileURLWithPath: "/x/Report.pdf")]), "Report")
        XCTAssertEqual(ArchiveCreator.defaultName(for: [URL(fileURLWithPath: "/x/Folder")]), "Folder")
    }
    func testDefaultNameMany() {
        XCTAssertEqual(ArchiveCreator.defaultName(for: [URL(fileURLWithPath: "/x/a"), URL(fileURLWithPath: "/x/b")]), String(localized: "Archive"))
    }

    // MARK: integration

    func makeSource() throws -> URL {
        let base = Fixtures.tempDir().appendingPathComponent("Proj")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try "a".write(to: base.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "junk".write(to: base.appendingPathComponent(".DS_Store"), atomically: true, encoding: .utf8)
        return base
    }

    func testCreateEveryFormatRoundTrip() async throws {
        for f in CreateFormat.allCases {
            let src = try makeSource()
            let dest = Fixtures.tempDir()
            var o = CreateOptions(name: "Out", destination: dest, format: f)
            if f.supportsPassword { o.password = nil }
            let result = try await ArchiveCreator(engine: .bundled).create(sources: [src], options: o)
            XCTAssertEqual(result.lastPathComponent, "Out.\(f.fileExtension)", "\(f)")
            var info = try await SevenZip.bundled.list(result, password: nil)
            if f.rawValue.hasPrefix("tar.") {   // compressed tar: list the inner tar
                let inner = Fixtures.tempDir()
                try await SevenZip.bundled.extract(result, items: [], to: inner, password: nil)
                info = try await SevenZip.bundled.list(inner.appendingPathComponent("Out.tar"), password: nil)
            }
            let paths = info.entries.map(\.path)
            XCTAssertTrue(paths.contains("Proj/a.txt"), "\(f): \(paths)")
            XCTAssertFalse(paths.contains { $0.hasSuffix(".DS_Store") }, "\(f)")
            XCTAssertEqual(Fixtures.listing(dest), ["Out.\(f.fileExtension)"], "\(f) leaves no staging")
        }
    }

    func testCreateWithPassword7z() async throws {
        let src = try makeSource()
        var o = CreateOptions(name: "S", destination: Fixtures.tempDir(), format: .sevenZip)
        o.password = "pw"; o.encryptNames = true
        let r = try await ArchiveCreator(engine: .bundled).create(sources: [src], options: o)
        do { _ = try await SevenZip.bundled.list(r, password: nil); XCTFail() } catch let e as EngineError { XCTAssertEqual(e, .passwordRequired) }
    }

    func testCreateSplitVolumes() async throws {
        let base = Fixtures.tempDir().appendingPathComponent("big")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: base.appendingPathComponent("r.bin").path, contents: Data((0..<3_000_000).map { _ in UInt8.random(in: 0...255) }))
        let dest = Fixtures.tempDir()
        var o = CreateOptions(name: "V", destination: dest, format: .sevenZip); o.level = .none; o.volumeSize = 1_000_000
        let r = try await ArchiveCreator(engine: .bundled).create(sources: [base], options: o)
        XCTAssertEqual(r.lastPathComponent, "V.7z.001")
        XCTAssertEqual(Fixtures.listing(dest), ["V.7z.001", "V.7z.002", "V.7z.003", "V.7z.004"].filter { FileManager.default.fileExists(atPath: dest.appendingPathComponent($0).path) })
        XCTAssertGreaterThanOrEqual(Fixtures.listing(dest).count, 3)
        let info = try await SevenZip.bundled.list(r, password: nil)
        XCTAssertTrue(info.entries.map(\.path).contains("big/r.bin"))
    }

    func testCreateNameCollision() async throws {
        let src = try makeSource()
        let dest = Fixtures.tempDir()
        try "x".write(to: dest.appendingPathComponent("Out.zip"), atomically: true, encoding: .utf8)
        let r = try await ArchiveCreator(engine: .bundled).create(sources: [src], options: CreateOptions(name: "Out", destination: dest))
        XCTAssertEqual(r.lastPathComponent, "Out 2.zip")
    }

    func testCreateMultipleSources() async throws {
        let dir = Fixtures.tempDir()
        let a = dir.appendingPathComponent("a.txt"), b = dir.appendingPathComponent("b.txt")
        try "a".write(to: a, atomically: true, encoding: .utf8); try "b".write(to: b, atomically: true, encoding: .utf8)
        let r = try await ArchiveCreator(engine: .bundled).create(sources: [a, b], options: CreateOptions(name: "M", destination: dir))
        let info = try await SevenZip.bundled.list(r, password: nil)
        XCTAssertEqual(Set(info.entries.map(\.path)), ["a.txt", "b.txt"])
    }
}
