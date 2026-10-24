import Foundation
import PigeonCore
import Testing
@testable import Pigeon

/// Nothing the driver saved is lost to a file the app can't read.
@MainActor
struct RouteStoreTests {
    let folder = FileManager.default.temporaryDirectory.appending(path: "RouteStoreTests-\(UUID().uuidString)")
    var url: URL { folder.appending(path: "routes.json") }

    func route(_ name: String) -> SavedRoute {
        let line = RouteLine(points: [GeoPoint(latitude: 42.355, longitude: -71.0656), GeoPoint(latitude: 42.365, longitude: -71.0656)])!
        return SavedRoute(name: name, line: line, maneuvers: [], savedAt: Date(timeIntervalSinceReferenceDate: 0))
    }

    @Test func routesSurviveARelaunch() throws {
        let store = RouteStore(url: url)
        store.add(route("Library"))
        var saved = try #require(store.routes.first)
        saved.recordDrive(.clean, at: Date(timeIntervalSinceReferenceDate: 10))
        store.update(saved)
        let again = RouteStore(url: url)
        #expect(again.routes == [saved])
        again.delete([saved.id])
        #expect(RouteStore(url: url).routes.isEmpty)
    }

    @Test func aNewerFileIsLeftAlone() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let newer = Data(#"{"version":99,"routes":[]}"#.utf8)
        try newer.write(to: url)
        let store = RouteStore(url: url)
        #expect(store.needsNewerApp)
        store.add(route("Market"))
        #expect(try Data(contentsOf: url) == newer)
    }

    @Test func aDamagedFileIsMovedAsideNotOverwritten() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: url)
        let store = RouteStore(url: url)
        #expect(store.routes.isEmpty && !store.needsNewerApp)
        let aside = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasPrefix("routes.damaged-") }
        #expect(aside.count == 1)
    }
}
