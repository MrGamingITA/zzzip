import XCTest
@testable import Zzzip

final class ErrorMapperTests: XCTestCase {
    func map(_ code: Int32, _ err: String, pw: Bool = true, name: String = "a.7z") -> EngineError? {
        ErrorMapper.map(exitCode: code, stderr: err, passwordProvided: pw, archiveName: name)
    }

    func testSuccessIsNil() { XCTAssertNil(map(0, "")) }
    func testWarningIsNil() { XCTAssertNil(map(1, "WARNING: something")) }

    func testWrongPassword7z() {
        XCTAssertEqual(map(2, "ERROR: Data Error in encrypted file. Wrong password? : a.txt"), .wrongPassword)
    }
    func testWrongPasswordZip() {
        XCTAssertEqual(map(2, "ERROR: Wrong password : a.txt\nERROR: Wrong password : r.bin"), .wrongPassword)
    }
    func testCRCFailedEncrypted() {
        XCTAssertEqual(map(2, "ERROR: CRC Failed in encrypted file. Wrong password? : r.bin"), .wrongPassword)
    }
    func testEncryptedHeadersWrongPassword() {
        XCTAssertEqual(map(2, "ERROR: h.7z : Cannot open encrypted archive. Wrong password?\n\nERRORS:\nHeaders Error"), .wrongPassword)
    }
    func testBreakWithoutPasswordMeansPasswordRequired() {
        XCTAssertEqual(map(255, "\n\nBreak signaled", pw: false), .passwordRequired)
    }
    func testWrongPasswordWithoutPasswordMeansRequired() {
        XCTAssertEqual(map(2, "ERROR: Wrong password : a.txt", pw: false), .passwordRequired)
    }
    func testNotArchive() {
        XCTAssertEqual(map(2, "ERROR: n.zip : n.zip\nOpen ERROR: Cannot open the file as [zip] archive\n\nERRORS:\nIs not archive", name: "n.zip"), .unsupportedFormat)
    }
    func testMissingVolume() {
        XCTAssertEqual(map(2, "ERROR: v.7z.001 : v.7z\nOpen ERROR: Cannot open the file as [7z] archive\n\nERRORS:\nUnexpected end of archive", name: "v.7z.001"), .missingVolume("v.7z.001"))
    }
    func testUnexpectedEndNotVolumeIsCorrupted() {
        if case .corrupted = map(2, "ERRORS:\nUnexpected end of archive", name: "a.zip") {} else { XCTFail() }
    }
    func testDiskFull() {
        XCTAssertEqual(map(2, "ERROR: errno=28 : No space left on device"), .diskFull)
    }
    func testCRCFailedPlain() {
        if case .corrupted = map(2, "ERROR: CRC Failed : a.txt") {} else { XCTFail() }
    }
    func testOtherFailure() {
        XCTAssertEqual(map(7, "Command Line Error:\nUnsupported command"), .failed(code: 7, message: "Command Line Error:\nUnsupported command"))
    }
    func testUserMessageLocalizedNotEmpty() {
        XCTAssertFalse(EngineError.wrongPassword.userMessage.isEmpty)
    }
}
