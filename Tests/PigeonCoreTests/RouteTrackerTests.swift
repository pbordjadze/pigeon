import Foundation
import Testing
@testable import PigeonCore

struct RouteTrackerTests {
    typealias R = TestRoutes

    @discardableResult
    func run(_ fixes: [LocationFix], tracker: inout RouteTracker) -> [RouteTracker.Phase] {
        fixes.map { tracker.update($0) }
    }

    @Test func aCleanDriveArrives() {
        var tracker = RouteTracker(line: R.northThenEast)
        let phases = run(R.drive(from: 0, to: 3000), tracker: &tracker)
        #expect(!phases.contains { if case .left = $0 { true } else { false } })
        #expect(tracker.phase == .arrived)
    }

    @Test func gpsWobbleInsideTheLimitIsStillOnRoute() {
        var tracker = RouteTracker(line: R.northThenEast)
        run(R.drive(from: 0, to: 1500, sideways: 30), tracker: &tracker)
        #expect(tracker.phase == .onRoute)
    }

    @Test func turningOffTheRouteIsCaughtWithinTwoFixes() {
        var tracker = RouteTracker(line: R.northThenEast)
        run(R.drive(from: 0, to: 1000), tracker: &tracker)
        // A wrong left turn at 1000 m: heading west.
        #expect(tracker.update(R.fix(east: -30, north: 1000, t: 80)) == .onRoute)
        #expect(tracker.update(R.fix(east: -50, north: 1000, t: 81)) == .onRoute)  // first off fix
        #expect(tracker.update(R.fix(east: -70, north: 1000, t: 82)) == .left(.offLine))
    }

    @Test func oneStrayFixIsForgiven() {
        var tracker = RouteTracker(line: R.northThenEast)
        run(R.drive(from: 0, to: 500), tracker: &tracker)
        #expect(tracker.update(R.fix(east: 80, north: 510, t: 40)) == .onRoute)
        #expect(tracker.update(R.fix(east: 0, north: 520, t: 41)) == .onRoute)
        #expect(tracker.update(R.fix(east: 80, north: 530, t: 42)) == .onRoute)
        #expect(tracker.update(R.fix(east: 0, north: 540, t: 43)) == .onRoute)
    }

    @Test func poorFixesNeitherCountNorClear() {
        var tracker = RouteTracker(line: R.northThenEast)
        run(R.drive(from: 0, to: 500), tracker: &tracker)
        #expect(tracker.update(R.fix(east: 80, north: 510, t: 40)) == .onRoute)
        // 200 m accuracy: unusable, so it neither resets the count nor adds to it.
        #expect(tracker.update(R.fix(east: 0, north: 520, t: 41, accuracy: 200)) == .onRoute)
        #expect(tracker.update(R.fix(east: 80, north: 530, t: 42)) == .left(.offLine))
    }

    @Test func aLooseFixNeedsToBeFurtherOffThanItsAccuracy() {
        var tracker = RouteTracker(line: R.northThenEast)
        run(R.drive(from: 0, to: 500), tracker: &tracker)
        // 45 m off with 48 m accuracy could be on the road.
        for t in 40..<45 {
            #expect(tracker.update(R.fix(east: 45, north: 510 + Double(t), t: TimeInterval(t), accuracy: 48)) == .onRoute)
        }
    }

    @Test func aUTurnOnTheRouteIsLeavingIt() {
        var tracker = RouteTracker(line: R.northThenEast)
        run(R.drive(from: 0, to: 1000), tracker: &tracker)
        var phase = tracker.phase
        for (i, north) in stride(from: 990.0, through: 900, by: -15).enumerated() {
            phase = tracker.update(R.fix(east: 3, north: north, t: 80 + TimeInterval(i), course: 180, speed: 14))
        }
        #expect(phase == .left(.wrongWay))
    }

    @Test func slowManoeuvresAreNotWrongWay() {
        var tracker = RouteTracker(line: R.northThenEast)
        run(R.drive(from: 0, to: 1000), tracker: &tracker)
        for i in 0..<6 {
            tracker.update(R.fix(east: 2, north: 1000 - Double(i), t: 80 + TimeInterval(i), course: 180, speed: 1))
        }
        #expect(tracker.phase == .onRoute)
    }

    @Test func aShortcutThatRejoinsLaterIsLeaving() {
        // Cut the corner diagonally from 1500 m north to the east leg: the far end of the cut is on
        // the line again, but much further along than the drive could have got by now.
        var tracker = RouteTracker(line: R.northThenEast)
        run(R.drive(from: 0, to: 1500), tracker: &tracker)
        var phase = tracker.phase
        for i in 1...8 {
            let f = Double(i) / 8
            phase = tracker.update(R.fix(east: 600 * f, north: 1500 + 500 * f, t: 108 + TimeInterval(i)))
            if case .left = phase { break }
        }
        #expect(phase == .left(.offLine))
    }

    @Test func aDriveStartingInAParkingLotJoins() {
        var tracker = RouteTracker(line: R.northThenEast)
        #expect(tracker.update(R.fix(east: 90, north: 10, t: 0)) == .joining)
        #expect(tracker.update(R.fix(east: 60, north: 10, t: 20)) == .joining)
        #expect(tracker.update(R.fix(east: 5, north: 20, t: 40)) == .onRoute)
        run(R.drive(from: 30, to: 3000, startTime: 41), tracker: &tracker)
        #expect(tracker.phase == .arrived)
    }

    @Test func startingFarFromTheRouteIsLeavingIt() {
        var tracker = RouteTracker(line: R.northThenEast)
        #expect(tracker.update(R.fix(east: 400, north: 0, t: 0)) == .left(.neverJoined))
    }

    @Test func startingMidwayIsLeavingIt() {
        // On the line, but 1.5 km along: a drive starts at the route's start.
        var tracker = RouteTracker(line: R.northThenEast)
        #expect(tracker.update(R.fix(east: 0, north: 1500, t: 0)) == .left(.neverJoined))
    }

    @Test func neverReachingTheLineTimesOut() {
        var tracker = RouteTracker(line: R.northThenEast)
        #expect(tracker.update(R.fix(east: 100, north: 0, t: 0)) == .joining)
        #expect(tracker.update(R.fix(east: 100, north: 0, t: 121)) == .left(.neverJoined))
    }

    @Test func signalLossIsNoticedAfterTheTimeout() {
        var tracker = RouteTracker(line: R.northThenEast)
        run(R.drive(from: 0, to: 300), tracker: &tracker)
        let last = tracker.lastUsableFixTime!
        #expect(!tracker.signalLost(at: last + 19))
        #expect(tracker.signalLost(at: last + 21))
    }

    @Test func aTunnelGapStillFindsTheDriverAhead() {
        // 60 s without fixes, then 840 m further on: within reach at the speeds allowed.
        var tracker = RouteTracker(line: R.northThenEast)
        run(R.drive(from: 0, to: 700), tracker: &tracker)
        let t = tracker.lastUsableFixTime! + 60
        #expect(tracker.update(R.fix(east: 0, north: 1540, t: t)) == .onRoute)
        #expect(abs(tracker.lastMatch!.along - 1540) < 1)
    }

    @Test func finalPhasesStayFinal() {
        var tracker = RouteTracker(line: R.northThenEast)
        #expect(tracker.update(R.fix(east: 400, north: 0, t: 0)) == .left(.neverJoined))
        #expect(tracker.update(R.fix(east: 0, north: 10, t: 1)) == .left(.neverJoined))
        #expect(!tracker.signalLost(at: 100))
    }

    @Test func outOfOrderFixesAreIgnored() {
        var tracker = RouteTracker(line: R.northThenEast)
        run(R.drive(from: 0, to: 500), tracker: &tracker)
        #expect(tracker.update(R.fix(east: 300, north: 100, t: 1)) == .onRoute)
    }
}
