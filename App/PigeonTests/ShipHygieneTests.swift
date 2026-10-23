import Foundation
import Testing
@testable import Pigeon

/// What the shipped bundle promises: the privacy manifest says nothing is collected or tracked, and
/// the app asks for location only while in use, with background updates only for a drive.
struct ShipHygieneTests {
    func plist(_ name: String) throws -> [String: Any] {
        let url = try #require(Bundle.main.url(forResource: name, withExtension: "xcprivacy"))
        let data = try Data(contentsOf: url)
        return try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    @Test func privacyManifestCollectsAndTracksNothing() throws {
        let manifest = try plist("PrivacyInfo")
        #expect(manifest["NSPrivacyTracking"] as? Bool == false)
        #expect((manifest["NSPrivacyTrackingDomains"] as? [Any])?.isEmpty == true)
        #expect((manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.isEmpty == true)
    }

    @Test func locationIsAskedForOnlyWhileInUse() {
        let info = Bundle.main.infoDictionary ?? [:]
        #expect(info["NSLocationWhenInUseUsageDescription"] is String)
        #expect(info["NSLocationAlwaysAndWhenInUseUsageDescription"] == nil)
        #expect(Set(info["UIBackgroundModes"] as? [String] ?? []) == ["audio", "location"])
    }
}
