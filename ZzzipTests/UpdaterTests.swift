import XCTest
@testable import Zzzip

final class UpdaterTests: XCTestCase {
    func testInfoPlistConfiguresSparkle() {
        let info = Bundle.main.infoDictionary!
        XCTAssertEqual(info["SUFeedURL"] as? String, "https://raw.githubusercontent.com/MrGamingITA/zzzip/main/appcast.xml")
        XCTAssertEqual(info["SUPublicEDKey"] as? String, "99X6hcDTFzEbU3Hzd+pBAyNHBBqql4Y15E8ggPoc5NU=")
        XCTAssertEqual(info["SUEnableAutomaticChecks"] as? Bool, true)       // on by default, user can turn it off
        XCTAssertEqual(info["SUAutomaticallyUpdate"] as? Bool, false)        // ask before installing
        XCTAssertEqual(info["SUScheduledCheckInterval"] as? Int, 86400)
        XCTAssertNotNil(Int(info["CFBundleVersion"] as? String ?? ""), "CFBundleVersion must be an integer Sparkle can compare")
    }

    func testCheckIntervals() {
        XCTAssertEqual(UpdateInterval.daily.seconds, 86_400)
        XCTAssertEqual(UpdateInterval.weekly.seconds, 604_800)
        XCTAssertEqual(UpdateInterval(seconds: 86_400), .daily)
        XCTAssertEqual(UpdateInterval(seconds: 604_800), .weekly)
        XCTAssertEqual(UpdateInterval(seconds: 3_600), .daily)             // anything shorter snaps to daily
        XCTAssertEqual(UpdateInterval(seconds: 2_000_000), .weekly)
    }

    func testFeedOverrideForTesting() {
        let d = UserDefaults(suiteName: "zzzip-upd-\(UUID().uuidString)")!
        XCTAssertNil(AppUpdater.feedOverride(defaults: d))
        d.set("http://127.0.0.1:8765/appcast.xml", forKey: "ZzzipFeedURL")
        XCTAssertEqual(AppUpdater.feedOverride(defaults: d), "http://127.0.0.1:8765/appcast.xml")
    }

    func testUpdaterStartsAndExposesSettings() {
        let u = AppUpdater.shared
        XCTAssertNotNil(u.updater)
        let before = u.automaticallyChecks
        u.automaticallyChecks = !before
        XCTAssertEqual(u.automaticallyChecks, !before)
        u.automaticallyChecks = before
    }
}
