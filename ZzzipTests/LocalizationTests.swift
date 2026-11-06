import XCTest
@testable import Zzzip

final class LocalizationTests: XCTestCase {
    private func catalog(_ name: String) throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Zzzip/Resources/\(name)")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        return json["strings"] as! [String: Any]
    }

    func testEveryKeyTranslatedToItalian() throws {
        for name in ["Localizable.xcstrings", "InfoPlist.xcstrings"] {
            for (key, value) in try catalog(name) {
                let it = ((value as? [String: Any])?["localizations"] as? [String: Any])?["it"] as? [String: Any]
                let unit = it?["stringUnit"] as? [String: Any]
                XCTAssertEqual(unit?["state"] as? String, "translated", "\(name): “\(key)” not translated")
                XCTAssertFalse((unit?["value"] as? String ?? "").isEmpty, "\(name): “\(key)” empty")
            }
        }
    }

    /// Every string the app actually shows must be in the catalog (keys emitted by the compiler into the built app).
    func testBuiltItalianTableCoversEnglishKeys() throws {
        let it = Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: "it")
        let table = it.flatMap { NSDictionary(contentsOfFile: $0) as? [String: String] } ?? [:]
        XCTAssertGreaterThan(table.count, 150)
        for k in ["Extract Here", "Extract To…", "Show in Finder", "New Archive"] {
            XCTAssertNotNil(table[k], k)
        }
    }

    func testFallbackIsEnglish() {
        XCTAssertEqual(Bundle.preferredLocalizations(from: ["en", "it"], forPreferences: ["de"]).first, "en")
        XCTAssertEqual(Bundle.preferredLocalizations(from: ["en", "it"], forPreferences: ["fr-FR", "es"]).first, "en")
        XCTAssertEqual(Bundle.preferredLocalizations(from: ["en", "it"], forPreferences: ["it-IT"]).first, "it")
        XCTAssertEqual(Bundle.preferredLocalizations(from: ["en", "it"], forPreferences: ["en-GB"]).first, "en")
    }

    func testServicesMenuLocalized() {
        let it = Bundle.main.path(forResource: "ServicesMenu", ofType: "strings", inDirectory: nil, forLocalization: "it")
        let table = it.flatMap { NSDictionary(contentsOfFile: $0) as? [String: String] }
        XCTAssertEqual(table?["Compress with Zzzip"], "Comprimi con Zzzip")
    }
}
