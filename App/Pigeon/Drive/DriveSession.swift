import AudioToolbox
import CoreLocation
import Foundation
import MapKit
import Observation
import os
import PigeonCore

/// One drive along a saved route: follows the location, decides what the screen shows, brings full
/// guidance back and finds a new route when the driver leaves the route, and records how the drive
/// went on the route the moment it ends, whether or not the screen is on. After the end it keeps
/// reading the location only to tell when the car has stopped (`Motion`), for at most
/// `settleAfterEnd` seconds.
///
/// The route's stage is fixed for the drive; leaving the route switches the rest of the drive to
/// `full` (CLAUDE.md › Safety).
@Observable
final class DriveSession {
    /// Driving directions from here to a place: Apple Maps' in the app, a stand-in in tests.
    typealias Directions = (GeoPoint) async throws -> (line: RouteLine, maneuvers: [Maneuver])
    /// Records a finished drive's outcome on its route and returns the route as it now stands.
    typealias Record = (SavedRoute.ID, RouteProgress.Outcome) -> SavedRoute?

    let routeID: SavedRoute.ID
    let name: String
    /// The route's stage when the drive began.
    let routeStage: Stage
    private(set) var line: RouteLine
    private(set) var maneuvers: [Maneuver]
    /// Whether this drive has left the route (or never reached it); from then on it shows `full`.
    private(set) var leftRoute = false
    /// Whether the drive was ever on the saved route: one that never was didn't leave it.
    private(set) var joinedSavedRoute = false
    /// Waiting for a new route after leaving this one.
    private(set) var rerouting = false
    private(set) var position: LocationFix?
    private(set) var screen: GuidanceScreen
    /// The route after this drive was recorded on it; set once, when the drive ends.
    private(set) var result: SavedRoute?
    private(set) var outcome: RouteProgress.Outcome?

    static let settleAfterEnd: TimeInterval = 120

    private var tracker: RouteTracker
    private var endTime: TimeInterval?
    private var rerouteAskedAt: TimeInterval = 0
    private var motion = Motion()
    private var now: TimeInterval
    private var tasks: [Task<Void, Never>] = []
    private var sessions: [AnyObject] = []
    private let destination: GeoPoint
    private let directions: Directions
    private let record: Record

    var stage: Stage { leftRoute ? .full : routeStage }

    /// Whether the car is moving at `date` (`Motion`): the screen's controls and the after-drive
    /// summary wait until it isn't.
    func isMoving(at date: Date = Date()) -> Bool {
        motion.isMoving(at: date.timeIntervalSinceReferenceDate)
    }

    init(route: SavedRoute, startTime: TimeInterval = Date().timeIntervalSinceReferenceDate,
         directions: @escaping Directions = DriveSession.appleMaps, record: @escaping Record) {
        routeID = route.id
        name = route.name
        routeStage = route.progress.stage
        line = route.line
        maneuvers = route.maneuvers
        destination = route.line.end
        now = startTime
        tracker = RouteTracker(line: route.line, startTime: startTime)
        screen = GuidanceScreen(map: .route(faint: false), banner: nil, status: .joining)
        self.directions = directions
        self.record = record
    }

    static func appleMaps(to destination: GeoPoint) async throws -> (line: RouteLine, maneuvers: [Maneuver]) {
        let place = CLLocation(latitude: destination.latitude, longitude: destination.longitude)
        return try await RouteBuilder.directions(to: MKMapItem(location: place, address: nil))
    }

    /// Starts following the location, in the background too, until the drive ends.
    func start() {
        // Held for the drive: While Using authorization, and updates with the screen locked.
        sessions = [CLServiceSession(authorization: .whenInUse), CLBackgroundActivitySession()]
        tasks.append(Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates(.automotiveNavigation) {
                    guard let self, !Task.isCancelled else { return }
                    if update.stationary { self.motion.stopped(at: Date().timeIntervalSinceReferenceDate) }
                    if let location = update.location { self.handle(LocationFix(location)) }
                }
            } catch {
                Log.drive.error("location updates ended: \(error.localizedDescription, privacy: .public)")
            }
        })
        // The clock that notices a lost signal when no fixes come at all.
        tasks.append(Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                self.tick(Date().timeIntervalSinceReferenceDate)
            }
        })
    }

    func handle(_ fix: LocationFix) {
        motion.update(fix)
        now = max(now, fix.time)
        guard outcome == nil else {
            stopOnceSettled()
            return
        }
        position = fix
        let before = tracker.phase
        let phase = tracker.update(fix)
        if !leftRoute && tracker.joined { joinedSavedRoute = true }
        if case .left(let reason) = phase, before != phase {
            Log.drive.info("left the route (\(String(describing: reason), privacy: .public)); rerouting")
            leftRoute = true
            rerouting = true
            rerouteAskedAt = now
            AudioServicesPlaySystemSound(1007)  // one chime, voice or not
            tasks.append(Task { [weak self] in await self?.reroute() })
        }
        refresh()
        if phase == .arrived { finish() }
    }

    func tick(_ time: TimeInterval) {
        now = max(now, time)
        guard outcome == nil else {
            stopOnceSettled()
            return
        }
        refresh()
    }

    /// After the end: stop reading the location once the car has stopped, or after
    /// `settleAfterEnd` seconds whatever it does.
    private func stopOnceSettled() {
        guard let endTime else { return }
        if !motion.isMoving(at: now) || now - endTime > Self.settleAfterEnd { stop() }
    }

    /// Ends the drive (on arrival, or when the driver ends it), stops following the location and
    /// records the outcome on the route, once.
    func finish() {
        guard outcome == nil else { return }
        let outcome: RouteProgress.Outcome
        if !joinedSavedRoute {
            outcome = .unchanged  // never on the route: neither learned nor left
        } else if leftRoute {
            outcome = .leftRoute
        } else {
            outcome = tracker.phase == .arrived ? .clean : .unchanged
        }
        self.outcome = outcome
        endTime = now
        stopOnceSettled()
        Log.drive.info("drive ended: \(String(describing: outcome), privacy: .public)")
        result = record(routeID, outcome)
    }

    func stop() {
        tasks.forEach { $0.cancel() }
        tasks = []
        sessions = []
    }

    private func refresh() {
        var screen = Guidance.screen(stage: stage, phase: tracker.phase, signalLost: tracker.signalLost(at: now),
                                     along: tracker.lastMatch?.along ?? 0, speed: position?.speed, maneuvers: maneuvers)
        if rerouting { screen = GuidanceScreen(map: .route(faint: false), banner: nil, status: .rerouting) }
        self.screen = screen
    }

    /// Asks for a route from here to the destination until one comes, then follows it in full. The
    /// new line starts where the car was when it was asked for, so the car's first fix on it is
    /// searched for as far along as it could have driven since (and no further: a new route that
    /// turns and comes back past the car mustn't be joined on its way back).
    private func reroute() async {
        while outcome == nil && !Task.isCancelled {
            do {
                let built = try await directions(destination)
                guard outcome == nil else { return }
                line = built.line
                maneuvers = built.maneuvers
                var settings = RouteTracker.Settings()
                settings.joinSearch = settings.joinSearch + settings.maximumSpeed * max(0, now - rerouteAskedAt)
                tracker = RouteTracker(line: built.line, startTime: now, settings: settings)
                rerouting = false
                refresh()
                return
            } catch {
                Log.drive.error("reroute failed, trying again: \(error.localizedDescription, privacy: .public)")
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    #if DEBUG
    /// A drive frozen `along` metres down `route` at `speed`, for demo scenarios: no location, no
    /// clock, no directions.
    convenience init(demo route: SavedRoute, along: Double, speed: Double, leftRoute: Bool = false,
                     arrived: Bool = false, record: @escaping Record) {
        // Fixes an hour ahead read as moving for the screenshot; an arrival's, long ago, as stopped.
        let base = arrived ? 0 : Date().timeIntervalSinceReferenceDate + 3600
        self.init(route: route, startTime: base, directions: { _ in throw CancellationError() }, record: record)
        var t = base
        var at = 0.0
        while at < along {
            handle(LocationFix(point: route.line.point(at: at), horizontalAccuracy: 5, speed: speed, time: t))
            at += max(speed, 10)
            t += 1
        }
        handle(LocationFix(point: route.line.point(at: along), horizontalAccuracy: 5, speed: speed, time: t))
        if arrived {
            handle(LocationFix(point: route.line.end, horizontalAccuracy: 5, speed: 0, time: t + 1))
        }
        if leftRoute {
            self.leftRoute = true
            rerouting = true
            refresh()
        }
    }
    #endif
}
