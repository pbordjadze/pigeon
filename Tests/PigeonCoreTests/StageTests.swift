import Foundation
import Testing
@testable import PigeonCore

struct StageTests {
    @Test func fiveCleanDrivesLearnARoute() {
        var progress = RouteProgress()
        #expect(progress.cleanDrivesToLearn == 5)
        var stages: [Stage] = []
        for _ in 0..<5 {
            progress.record(.clean)
            stages.append(progress.stage)
        }
        #expect(stages == [.landmarks, .turnsOnly, .quiet, .quiet, .quiet])
        #expect(progress.isLearned)
        #expect(progress.cleanDrivesToLearn == 0)
    }

    @Test func leavingTheRouteStepsBackOneAndRestartsTheQuietCount() {
        var progress = RouteProgress(stage: .quiet, quietCleanDrives: 1)
        progress.record(.leftRoute)
        #expect(progress == RouteProgress(stage: .turnsOnly))
        progress.record(.clean)
        #expect(progress.stage == .quiet && progress.quietCleanDrives == 0)
        progress.record(.leftRoute)
        progress.record(.leftRoute)
        progress.record(.leftRoute)
        progress.record(.leftRoute)
        #expect(progress.stage == .full)
    }

    @Test func anUnfinishedDriveChangesNothing() {
        var progress = RouteProgress(stage: .landmarks)
        progress.record(.unchanged)
        #expect(progress == RouteProgress(stage: .landmarks))
    }

    @Test func decodingIsForgiving() throws {
        let decoder = JSONDecoder()
        // A stage from a newer app reads as full; a count at a stage without one is dropped.
        let future = try decoder.decode(RouteProgress.self, from: Data(#"{"stage":9,"quietCleanDrives":4}"#.utf8))
        #expect(future == RouteProgress(stage: .full))
        let round = try decoder.decode(RouteProgress.self, from: JSONEncoder().encode(RouteProgress(stage: .quiet, quietCleanDrives: 1)))
        #expect(round == RouteProgress(stage: .quiet, quietCleanDrives: 1))
        #expect(try decoder.decode(Turn.self, from: Data(#""roundabout""#.utf8)) == .straight)
    }

    @Test func turnsFromGeometry() {
        let line = TestRoutes.northThenEast
        #expect(line.turn(at: 2000) == .right)
        #expect(line.turn(at: 1000) == .straight)
        #expect(Turn(angle: -90) == .left)
        #expect(Turn(angle: 30) == .slightRight)
        #expect(Turn(angle: -150) == .sharpLeft)
        #expect(Turn(angle: 179) == .uTurn)
    }
}

struct GuidanceTests {
    let maneuvers = [
        Maneuver(along: 2000, turn: .right, instruction: "Turn right onto Beacon Street", landmark: "the State House"),
        Maneuver(along: 2600, turn: .left, instruction: "Turn left onto Park Street"),
    ]

    func screen(_ stage: Stage, along: Double, speed: Double? = 14, phase: RouteTracker.Phase = .onRoute,
                signalLost: Bool = false) -> GuidanceScreen {
        Guidance.screen(stage: stage, phase: phase, signalLost: signalLost, along: along, speed: speed, maneuvers: maneuvers)
    }

    @Test func fullShowsDistanceAndStreet() {
        let s = screen(.full, along: 1500)
        #expect(s.map == .route(faint: false))
        #expect(s.banner == .init(turn: .right, distance: 500, instruction: "Turn right onto Beacon Street", landmark: nil))
    }

    @Test func landmarksNameTheTurnWithoutDistance() {
        #expect(screen(.landmarks, along: 1500).banner == .init(turn: .right, distance: nil, instruction: nil, landmark: "the State House"))
        // No landmark found: the instruction instead.
        #expect(screen(.landmarks, along: 2100).banner == .init(turn: .left, distance: nil, instruction: "Turn left onto Park Street", landmark: nil))
        #expect(screen(.landmarks, along: 1500).map == .route(faint: true))
    }

    @Test func turnsOnlyCuesFifteenSecondsAhead() {
        #expect(screen(.turnsOnly, along: 1500).banner == nil)             // 500 m at 14 m/s: 36 s away
        #expect(screen(.turnsOnly, along: 1800).banner?.turn == .right)    // 200 m: 14 s away
        #expect(screen(.turnsOnly, along: 1800, speed: 5).banner == nil)   // slow: 40 s away
        #expect(screen(.turnsOnly, along: 1860, speed: nil).banner?.turn == .right)  // within 150 m
        #expect(screen(.turnsOnly, along: 1800).map == .roadsOnly)
        #expect(screen(.turnsOnly, along: 1800).banner?.instruction == nil)
    }

    @Test func aTurnJustMadeGivesWayToTheNext() {
        #expect(screen(.full, along: 1995).banner?.turn == .right)
        #expect(screen(.full, along: 2015).banner?.turn == .left)
        #expect(screen(.full, along: 2700).banner == nil)
    }

    @Test func quietShowsNothing() {
        #expect(screen(.quiet, along: 1990) == GuidanceScreen(map: .hidden, banner: nil, status: .onRoute))
    }

    @Test func helpComesBackWhateverTheStage() {
        for stage in Stage.allCases {
            #expect(screen(stage, along: 1500, phase: .left(.offLine)).map == .route(faint: false))
            #expect(screen(stage, along: 1500, phase: .left(.offLine)).status == .rerouting)
            #expect(screen(stage, along: 0, phase: .joining).map == .route(faint: false))
            let lost = screen(stage, along: 1500, signalLost: true)
            #expect(lost.map == .route(faint: false) && lost.status == .signalLost)
            #expect(lost.banner?.distance == 500)
        }
    }
}

struct SavedRouteTests {
    func route() -> SavedRoute {
        SavedRoute(name: "To the market", line: TestRoutes.northThenEast,
                   maneuvers: [Maneuver(along: 2600, turn: .left), Maneuver(along: 2000, turn: .right)],
                   savedAt: Date(timeIntervalSinceReferenceDate: 0))
    }

    @Test func maneuversAreKeptInRouteOrder() {
        #expect(route().maneuvers.map(\.along) == [2000, 2600])
    }

    @Test func aDriveMovesTheStage() {
        var r = route()
        r.recordDrive(.clean, at: Date(timeIntervalSinceReferenceDate: 100))
        #expect(r.progress.stage == .landmarks)
        #expect(r.lastDriven == Date(timeIntervalSinceReferenceDate: 100))
    }

    @Test func theFileRoundTripsAndRefusesANewerOne() throws {
        let file = RouteFile(routes: [route()])
        #expect(try RouteFile.read(file.write()) == file)
        let newer = Data(#"{"version":2,"routes":[]}"#.utf8)
        #expect(throws: RouteFile.ReadError.newerVersion(2)) { try RouteFile.read(newer) }
        #expect(throws: (any Error).self) { try RouteFile.read(Data("not json".utf8)) }
    }
}

struct MotionTests {
    typealias R = TestRoutes

    @Test func aMovingCarStaysMovingThroughAShortStop() {
        var motion = Motion()
        motion.update(R.fix(east: 0, north: 0, t: 0, speed: 14))
        #expect(motion.isMoving(at: 0))
        motion.update(R.fix(east: 0, north: 10, t: 1, speed: 0))
        #expect(motion.isMoving(at: 5))
        #expect(!motion.isMoving(at: 11))
    }

    @Test func aMissingSpeedIsEstimatedFromTheFixes() {
        var motion = Motion()
        motion.update(R.fix(east: 0, north: 0, t: 0))
        motion.update(R.fix(east: 0, north: 15, t: 1))   // 15 m in a second, 5 m fixes, no speed
        #expect(motion.isMoving(at: 1))
    }

    @Test func aMovingCarWithLooseFixesAndNoSpeedStaysMoving() {
        // 14 m/s on 30 m fixes, never a speed reading: moving within 10 s, and it stays moving.
        var motion = Motion()
        for t in 0...60 {
            motion.update(R.fix(east: 0, north: Double(t) * 14, t: TimeInterval(t), accuracy: 30))
            if t >= 10 { #expect(motion.isMoving(at: TimeInterval(t)), "at \(t) s") }
        }
    }

    @Test func aGuessNeverClearsAReportedSpeed() {
        var motion = Motion()
        motion.update(R.fix(east: 0, north: 0, t: 0, accuracy: 30, speed: 30))
        for t in 1...30 {
            motion.update(R.fix(east: 0, north: Double(t) * 30, t: TimeInterval(t), accuracy: 30))
            #expect(motion.isMoving(at: TimeInterval(t)), "at \(t) s")
        }
    }

    @Test func aStopWithNoSpeedReadingsUnlocksWithinHalfAMinute() {
        // 14 m/s on 30 m fixes with no speed, then parked with fixes still coming.
        var motion = Motion()
        for t in 0...30 { motion.update(R.fix(east: 0, north: Double(t) * 14, t: TimeInterval(t), accuracy: 30)) }
        for t in 31...60 { motion.update(R.fix(east: 0, north: 420, t: TimeInterval(t), accuracy: 30)) }
        #expect(!motion.isMoving(at: 60))
        // And then the updates pause: still not moving.
        #expect(!motion.isMoving(at: 100))
    }

    @Test func oneJumpIndoorsLocksBriefly() {
        var motion = Motion()
        for t in 0...20 { motion.update(R.fix(east: 0, north: 0, t: TimeInterval(t), accuracy: 50)) }
        motion.update(R.fix(east: 150, north: 0, t: 21, accuracy: 50))
        for t in 22...45 { motion.update(R.fix(east: 0, north: 0, t: TimeInterval(t), accuracy: 50)) }
        #expect(!motion.isMoving(at: 45))
        #expect(!motion.isMoving(at: 90))   // updates paused after: no two-minute lock
    }

    @Test func stationaryFromCoreLocationIsStopped() {
        var motion = Motion()
        motion.update(R.fix(east: 0, north: 0, t: 0, speed: 14))
        motion.stopped(at: 2)
        #expect(!motion.isMoving(at: 2))
        #expect(!motion.isMoving(at: 60))
    }

    @Test func aParkedPhoneWithLooseFixesIsStill() {
        // Indoors: 40 m fixes jumping 30-60 m about, no speed reported.
        var motion = Motion()
        let jumps: [(Double, Double)] = [(0, 0), (45, 10), (-10, 40), (30, -20), (-40, 5), (20, 50)]
        for (i, (e, n)) in jumps.enumerated() {
            motion.update(R.fix(east: e, north: n, t: TimeInterval(i), accuracy: 40))
        }
        #expect(!motion.isMoving(at: 5))
    }

    @Test func noFixesAfterMovingIsMovingForAWhile() {
        var motion = Motion()
        motion.update(R.fix(east: 0, north: 0, t: 0, speed: 14))
        #expect(motion.isMoving(at: 60))     // a tunnel: unknown counts as moving
        #expect(!motion.isMoving(at: 130))   // not forever
    }

    @Test func noFixesAfterStoppingIsStopped() {
        var motion = Motion()
        motion.update(R.fix(east: 0, north: 0, t: 0, speed: 14))
        motion.update(R.fix(east: 0, north: 5, t: 1, speed: 0))
        #expect(!motion.isMoving(at: 30))
    }
}
