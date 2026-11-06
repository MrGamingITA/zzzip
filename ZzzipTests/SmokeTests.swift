import XCTest
@testable import Zzzip

final class SmokeTests: XCTestCase {
    func testBundled7zzRuns() throws {
        let p = Process()
        p.executableURL = SevenZip.bundledExecutable
        p.arguments = ["i"]
        let out = Pipe(); p.standardOutput = out
        p.standardInput = FileHandle.nullDevice
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("7-Zip (z) 26.05"))
    }

    func testItalianLocalizationPresent() {
        XCTAssertTrue(Bundle.main.localizations.contains("it"))
        XCTAssertTrue(Bundle.main.localizations.contains("en"))
    }
}
