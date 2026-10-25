import Foundation
import PigeonCore
import Testing
@testable import Pigeon

/// Drives fed fix by fix: what the screen shows and what is recorded on the route.
@MainActor
struct DriveSessionTests {
    static let origin = GeoPoint(latitude: 42.3550, longitude: -71.0656)

    static func point(_ east: Double, _ north: Double) -> GeoPoint {
        let metres = 111_195.0
        return GeoPoint(latitude: origin.latitude + north / metres,
                        longitude: origin.longitude + east / (metres * cos(origin.latitude * .pi / 180)))
    }

    /// 2 km north, then 1 km east, at `stage`.
    func route(_ stage: Stage) -> SavedRoute {
        let line = RouteLine(points: [Self.point(0, 0), Self.point(0, 2000), Self.point(1000, 2000)])!
        return SavedRoute(name: "Test", line: line, maneuvers: [Maneuver(along: 2000, turn: .right)],
                          progress: RouteProgress(stage: stage), savedAt: Date(timeIntervalSinceReferenceDate: 0))
    }

    /// Records outcomes the way RootView's store does, counting them.
    final class Recorder {
        var route: SavedRoute
        var outcomes: [RouteProgress.Outcome] = []
        init(_ route: SavedRoute) { self.route = route }
        func record(_ id: SavedRoute.ID, _ outcome: RouteProgress.Outcome) -> SavedRoute? {
            outcomes.append(outcome)
            route.recordDrive(outcome, at: Date())
            return route
        }
    }

    func fix(_ east: Double, _ north: Double, _ t: Double, speed: Double = 14) -> LocationFix {
        LocationFix(point: Self.point(east, north), horizontalAccuracy: 5, speed: speed, time: t)
    }

    /// A new route from wherever the car is now to the destination, going east then north.
    func directions(from session: @escaping () -> DriveSession?) -> DriveSession.Directions {
        { _, _ in
            let here = session()?.position?.point ?? Self.origin
            let line = RouteLine(points: [here, GeoPoint(latitude: here.latitude, longitude: Self.point(1000, 0).longitude),
                                          Self.point(1000, 2000)])!
            return (line, [])
        }
    }

    func waitForReroute(_ session: DriveSession) async {
        for _ in 0..<200 where session.rerouting { await Task.yield() }
    }

    @Test func aCleanDriveMovesTheRouteUpOnce() {
        let recorder = Recorder(route(.landmarks))
        let session = DriveSession(route: recorder.route, startTime: 0, record: recorder.record)
        var t = 0.0
        for along in stride(from: 0.0, through: 3000, by: 14) {
            let (e, n) = along <= 2000 ? (0.0, along) : (along - 2000, 2000.0)
            session.handle(fix(e, n, t)); t += 1
        }
        #expect(recorder.outcomes == [.clean])
        #expect(session.result?.progress.stage == .turnsOnly)
        session.handle(fix(1000, 2000, t + 5))
        session.finish()
        #expect(recorder.outcomes == [.clean])
    }

    @Test func leavingTheRouteShowsEverythingAndRecordsLeftAfterArriving() async {
        let recorder = Recorder(route(.quiet))
        var session: DriveSession?
        session = DriveSession(route: recorder.route, startTime: 0, directions: directions(from: { session }), record: recorder.record)
        let s = session!
        var t = 0.0
        for north in stride(from: 0.0, through: 600, by: 14) { s.handle(fix(0, north, t)); t += 1 }
        #expect(s.screen.map == .hidden)
        // A wrong right turn at 600 m.
        for east in stride(from: 20.0, through: 120, by: 14) { s.handle(fix(east, 600, t)); t += 1 }
        #expect(s.leftRoute && s.stage == .full)
        #expect(s.screen.status == .rerouting && s.screen.map == .route(faint: false))
        await waitForReroute(s)
        #expect(!s.rerouting)
        // More than 500 m along the new route by the time it came (the old join limit): still on
        // it, at full.
        t += 40
        s.handle(fix(700, 600, t)); t += 1
        #expect(s.screen.status == .onRoute && s.screen.map == .route(faint: false))
        for east in stride(from: 714.0, through: 1000, by: 14) { s.handle(fix(east, 600, t)); t += 1 }
        for north in stride(from: 600.0, through: 2000, by: 14) { s.handle(fix(1000, north, t)); t += 1 }
        #expect(recorder.outcomes == [.leftRoute])
        #expect(s.result?.progress.stage == .turnsOnly)
    }

    @Test func startingAwayFromTheRouteDoesNotCountAsLeavingIt() async {
        let recorder = Recorder(route(.turnsOnly))
        var session: DriveSession?
        session = DriveSession(route: recorder.route, startTime: 0, directions: directions(from: { session }), record: recorder.record)
        let s = session!
        s.handle(fix(-600, 0, 0))   // 600 m from the route's start
        #expect(s.leftRoute && s.screen.status == .rerouting)
        await waitForReroute(s)
        s.finish()
        #expect(recorder.outcomes == [.unchanged])
        #expect(s.result?.progress.stage == .turnsOnly)
    }

    @Test func endingADriveEarlyChangesNothing() {
        let recorder = Recorder(route(.landmarks))
        let session = DriveSession(route: recorder.route, startTime: 0, record: recorder.record)
        for (i, north) in stride(from: 0.0, through: 700, by: 14).enumerated() { session.handle(fix(0, north, Double(i))) }
        session.finish()
        #expect(recorder.outcomes == [.unchanged])
    }

    @Test func losingTheSignalAtQuietShowsTheRoute() {
        let recorder = Recorder(route(.quiet))
        let session = DriveSession(route: recorder.route, startTime: 0, record: recorder.record)
        for (i, north) in stride(from: 0.0, through: 700, by: 14).enumerated() { session.handle(fix(0, north, Double(i))) }
        #expect(session.screen.map == .hidden)
        session.tick(80)
        #expect(session.screen.status == .signalLost && session.screen.map == .route(faint: false))
    }

    @Test func aLongRedLightIsNotALostSignalButATunnelAfterItIs() {
        let recorder = Recorder(route(.quiet))
        let session = DriveSession(route: recorder.route, startTime: 0, record: recorder.record)
        for (i, north) in stride(from: 0.0, through: 700, by: 14).enumerated() { session.handle(fix(0, north, Double(i))) }
        session.reportStationary(true, at: 51)
        session.tick(120)   // 70 s with no fixes, still at the light
        #expect(session.screen.status == .onRoute && session.screen.map == .hidden)
        session.tick(400)   // no update ever said it moved: after the hold, the signal is lost
        #expect(session.screen.status == .signalLost && session.screen.map == .route(faint: false))
    }

    @Test func theCarCountsAsMovingWithoutASpeedReading() {
        let recorder = Recorder(route(.full))
        let session = DriveSession(route: recorder.route, startTime: 0, record: recorder.record)
        for i in 0...12 {
            session.handle(LocationFix(point: Self.point(0, Double(i) * 14), horizontalAccuracy: 30, time: 100 + Double(i)))
        }
        #expect(session.isMoving(at: Date(timeIntervalSinceReferenceDate: 112)))
        #expect(!session.isMoving(at: Date(timeIntervalSinceReferenceDate: 300)))
    }

    @Test func theRouteGoneFromTheListStillEndsTheDrive() {
        let session = DriveSession(route: route(.full), startTime: 0, record: { _, _ in nil })
        session.handle(fix(0, 0, 0))
        session.finish()
        #expect(session.outcome == .unchanged && session.result == nil)
    }

    @Test func aDemoDriveRecordsOnItsOwnCopyOnly() {
        let session = DriveSession.demo(stage: .landmarks, wrongTurn: false)
        #expect(session.isDemo && session.routeStage == .landmarks)
        var simulation = DriveSimulation(line: SampleRoute.line)
        var t = 0.0
        while let fix = simulation.next(following: session.line, at: t) { session.handle(fix); t += 0.25 }
        #expect(session.outcome == .clean)
        #expect(session.result?.progress.stage == .turnsOnly)
    }
}
