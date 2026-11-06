import XCTest
@testable import Zzzip

final class ExtractionPlannerTests: XCTestCase {
    let dest = Fixtures.tempDir()

    func testSingleItemGoesLoose() {
        XCTAssertNil(ExtractionPlanner.containerFolder(archiveURL: URL(fileURLWithPath: "/x/Progetto.zip"), topLevelCount: 1, destination: dest, mode: .smart))
    }
    func testManyItemsGetFolder() {
        XCTAssertEqual(ExtractionPlanner.containerFolder(archiveURL: URL(fileURLWithPath: "/x/Progetto.zip"), topLevelCount: 3, destination: dest, mode: .smart),
                       dest.appendingPathComponent("Progetto"))
    }
    func testFolderExistsGetsNumber() throws {
        try FileManager.default.createDirectory(at: dest.appendingPathComponent("Progetto"), withIntermediateDirectories: true)
        XCTAssertEqual(ExtractionPlanner.containerFolder(archiveURL: URL(fileURLWithPath: "/x/Progetto.zip"), topLevelCount: 3, destination: dest, mode: .smart)?.lastPathComponent,
                       "Progetto 2")
    }
    func testLooseModeNeverFolder() {
        XCTAssertNil(ExtractionPlanner.containerFolder(archiveURL: URL(fileURLWithPath: "/x/P.zip"), topLevelCount: 5, destination: dest, mode: .loose))
    }
    func testStripsDoubleExtension() {
        XCTAssertEqual(ExtractionPlanner.baseName(of: URL(fileURLWithPath: "/x/x.tar.gz")), "x")
        XCTAssertEqual(ExtractionPlanner.baseName(of: URL(fileURLWithPath: "/x/my.backup.tgz")), "my.backup")
    }
    func testStripsVolumeSuffix() {
        XCTAssertEqual(ExtractionPlanner.baseName(of: URL(fileURLWithPath: "/x/x.part1.rar")), "x")
        XCTAssertEqual(ExtractionPlanner.baseName(of: URL(fileURLWithPath: "/x/x.7z.001")), "x")
    }
    func testUniqueNameFile() throws {
        let f = dest.appendingPathComponent("a.txt")
        XCTAssertEqual(UniqueName.next(for: f), f)
        try "1".write(to: f, atomically: true, encoding: .utf8)
        XCTAssertEqual(UniqueName.next(for: f).lastPathComponent, "a 2.txt")
        try "2".write(to: dest.appendingPathComponent("a 2.txt"), atomically: true, encoding: .utf8)
        XCTAssertEqual(UniqueName.next(for: f).lastPathComponent, "a 3.txt")
    }
    func testUniqueNameDoubleExtension() throws {
        let f = dest.appendingPathComponent("a.tar.gz")
        try "1".write(to: f, atomically: true, encoding: .utf8)
        XCTAssertEqual(UniqueName.next(for: f).lastPathComponent, "a 2.tar.gz")
    }
}
