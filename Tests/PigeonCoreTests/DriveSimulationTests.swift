import Foundation
import Testing
@testable import PigeonCore

struct DriveSimulationTests {
    /// Plays a simulation against trackers as the app's drive does: on leaving the route, a new
    /// tracker on `SampleRoute.reroute` from where the car is. Returns the phases seen in order.
    func play(_ simulation: inout DriveSimulation, interval: TimeInterval = 0.25) -> [RouteTracker.Phase] {
        var line = SampleRoute.line
        var tracker = RouteTracker(line: line, startTime: 0)
        var phases: [RouteTracker.Phase] = []
        var t = 0.0
        while let fix = simulation.next(following: line, at: t) {
            let phase = tracker.update(fix)
            if phases.last != phase { phases.append(phase) }
            if case .left = phase, tracker.line == SampleRoute.line, let reroute = SampleRoute.reroute(from: fix.point) {
                line = reroute.line
                var settings = RouteTracker.Settings()
                settings.joinSearch = reroute.line.length
                tracker = RouteTracker(line: line, startTime: t, settings: settings)
            }
            t += interval
            if t > 600 { break }
        }
        return phases
    }

    @Test func aCleanDemoDriveArrives() {
        var simulation = DriveSimulation(line: SampleRoute.line)
        let phases = play(&simulation)
        #expect(phases == [.onRoute, .arrived])
        #expect(simulation.isFinished)
    }

    @Test func aWrongTurnLeavesTheRouteThenArrivesOnTheReroute() {
        var simulation = DriveSimulation(line: SampleRoute.line, wrongTurnAt: 600)
        let phases = play(&simulation)
        #expect(phases.first == .onRoute)
        #expect(phases.contains(.left(.offLine)))
        #expect(phases.last == .arrived)
    }

    @Test func theWrongTurnGoesOffToTheRight() {
        var simulation = DriveSimulation(line: SampleRoute.line, wrongTurnAt: 600)
        var last: LocationFix?
        for i in 0..<14 { last = simulation.next(following: SampleRoute.line, at: Double(i)) }
        let match = SampleRoute.line.match(last!.point)!
        #expect(match.offset > 100)
        #expect(last!.course.map { abs(Geo.turn(from: 0, to: $0) - 90) < 1 } == true)
    }

    @Test func theSampleRouteIsWhatItSays() {
        #expect(abs(SampleRoute.line.length - 3600) < 2)
        #expect(SampleRoute.line.turn(at: 1200) == .right)
        #expect(SampleRoute.line.turn(at: 2100) == .left)
        #expect(SampleRoute.line.turn(at: 3000) == .right)
        #expect(abs(Geo.distance(Geo.offset(SampleRoute.origin, bearing: 90, distance: 100), SampleRoute.origin) - 100) < 0.5)
    }
}
