#if DEBUG
import Foundation
import os
import PigeonCore

/// Deterministic, launch-argument-driven app states for screenshots and UI tests.
///
///     xcrun simctl launch <udid> com.pbordjadze.pigeon -demo drive-turns
///
/// Scenario names are owned by the views that render them (`RootView`, `DriveView`,
/// `AddRouteView`). Scenarios named `*-dark` are captured in dark appearance and `*-long-text`
/// with every localized string doubled (`ci/screenshots.sh`); the rest of the name picks the state.
/// Demo routes are made up, laid out in metres from a public place (CLAUDE.md › Map).
///
/// Debug builds only: the demo types are compiled out of Release builds, so a shipped app has no
/// launch argument that swaps its content (`ci/check_release.sh` checks).
enum DemoMode {
    /// The requested scenario, e.g. "routes-empty".
    static let scenario: String? = UserDefaults.standard.string(forKey: "demo")

    static var isActive: Bool { scenario != nil }

    /// The scenario's name without its `-dark` and `-long-text` variants.
    private static var base: String? {
        scenario?.replacingOccurrences(of: "-long-text", with: "").replacingOccurrences(of: "-dark", with: "")
    }

    enum Screen {
        case list
        case addRoute
        case drive(DriveSession)
    }

    /// The routes a demo launch starts with; nil when not a demo.
    static var routes: [SavedRoute]? {
        guard let base else { return nil }
        if base == "routes-empty" { return [] }
        return sampleRoutes
    }

    /// What the scenario opens over the route list.
    static var screen: Screen? {
        guard let base else { return nil }
        let route = sampleRoutes[0]
        func at(_ stage: Stage) -> SavedRoute {
            var r = route
            r.progress = RouteProgress(stage: stage)
            return r
        }
        switch base {
        case "routes-empty", "routes-list": return .list
        case "add-route": return .addRoute
        case "drive-full": return .drive(DriveSession(demo: at(.full), along: 900, speed: 14))
        case "drive-landmarks": return .drive(DriveSession(demo: at(.landmarks), along: 900, speed: 14))
        case "drive-turns": return .drive(DriveSession(demo: at(.turnsOnly), along: 1020, speed: 14))
        case "drive-quiet": return .drive(DriveSession(demo: at(.quiet), along: 900, speed: 14))
        case "drive-rerouting": return .drive(DriveSession(demo: at(.turnsOnly), along: 900, speed: 14, leftRoute: true))
        case "arrival-clean": return .drive(DriveSession(demo: at(.landmarks), along: route.line.length - 60, speed: 8, arrived: true))
        default: return .list
        }
    }

    /// Four made-up routes around Boston Common, one at each stage; the first has three turns.
    static let sampleRoutes: [SavedRoute] = {
        let origin = GeoPoint(latitude: 42.3550, longitude: -71.0656)
        func p(_ east: Double, _ north: Double) -> GeoPoint {
            let metresPerDegree = 111_195.0
            return GeoPoint(latitude: origin.latitude + north / metresPerDegree,
                            longitude: origin.longitude + east / (metresPerDegree * cos(origin.latitude * .pi / 180)))
        }
        let line = RouteLine(points: [p(0, 0), p(0, 1200), p(900, 1200), p(900, 2100), p(1500, 2100)])!
        let turns = [
            Maneuver(along: 1200, turn: .right, instruction: "Turn right onto Charles Street", landmark: "Public Garden"),
            Maneuver(along: 2100, turn: .left, instruction: "Turn left onto Beacon Street"),
            Maneuver(along: 3000, turn: .right, instruction: "Turn right onto Park Street", landmark: "State House"),
        ]
        let saved = Date(timeIntervalSinceReferenceDate: 800_000_000)
        return [
            SavedRoute(name: "Harbor Office", line: line, maneuvers: turns, progress: RouteProgress(stage: .full), savedAt: saved),
            SavedRoute(name: "Riverside Gym", line: line, maneuvers: turns, progress: RouteProgress(stage: .landmarks), savedAt: saved),
            SavedRoute(name: "Market", line: line, maneuvers: turns, progress: RouteProgress(stage: .turnsOnly), savedAt: saved),
            SavedRoute(name: "Library", line: line, maneuvers: turns, progress: RouteProgress(stage: .quiet, quietCleanDrives: 1), savedAt: saved),
        ]
    }()

    /// `tmp/demo-ready` in the app's data container. CI screenshots a scenario shortly after
    /// this file appears instead of sleeping for a worst-case delay.
    static let readyMarker = FileManager.default.temporaryDirectory.appending(path: "demo-ready")

    /// Signals that the scenario's content is on screen; only animations are still settling.
    static func markReady() {
        guard isActive else { return }
        FileManager.default.createFile(atPath: readyMarker.path, contents: Data())
        Log.demo.info("demo-ready \(scenario ?? "", privacy: .public)")
    }
}
#endif
