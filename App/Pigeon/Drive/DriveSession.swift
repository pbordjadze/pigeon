import AudioToolbox
import CoreLocation
import Foundation
import MapKit
import Observation
import os
import PigeonCore

/// One drive along a saved route: follows the location, decides what the screen shows, and when
/// the driver leaves the route brings full guidance back and finds a new route to the destination.
///
/// The route's stage is fixed for the drive; leaving the route switches the rest of the drive to
/// `full` (CLAUDE.md › Safety). The outcome, recorded at the end, moves the route's stage.
@Observable
final class DriveSession {
    let routeID: SavedRoute.ID
    let name: String
    /// The route's stage when the drive began.
    let routeStage: Stage
    private(set) var line: RouteLine
    private(set) var maneuvers: [Maneuver]
    /// Whether this drive has left the route; from then on it shows `full`.
    private(set) var leftRoute = false
    private(set) var position: LocationFix?
    private(set) var screen: GuidanceScreen
    private(set) var finished = false

    private var tracker: RouteTracker
    private var now: TimeInterval
    private var tasks: [Task<Void, Never>] = []
    private var sessions: [AnyObject] = []
    private let destination: GeoPoint

    var stage: Stage { leftRoute ? .full : routeStage }
    /// Faster than walking pace: the screen's controls wait until the car stops.
    var isMoving: Bool { (position?.speed ?? 0) > 2 }

    /// How the drive went, once it is over: clean if it arrived without ever leaving the route.
    var outcome: RouteProgress.Outcome {
        if leftRoute { return .leftRoute }
        return screen.status == .arrived ? .clean : .unchanged
    }

    init(route: SavedRoute, startTime: TimeInterval = Date().timeIntervalSinceReferenceDate) {
        routeID = route.id
        name = route.name
        routeStage = route.progress.stage
        line = route.line
        maneuvers = route.maneuvers
        destination = route.line.end
        now = startTime
        tracker = RouteTracker(line: route.line, startTime: startTime)
        screen = GuidanceScreen(map: .route(faint: false), banner: nil, status: .joining)
    }

    /// Starts following the location: in the background too, until `stop()`.
    func start() {
        // Held for the drive: While Using authorization, and updates with the screen locked.
        sessions = [CLServiceSession(authorization: .whenInUse), CLBackgroundActivitySession()]
        tasks.append(Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates(.automotiveNavigation) {
                    guard let self, !self.finished else { return }
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
                guard let self, !self.finished else { return }
                self.now = Date().timeIntervalSinceReferenceDate
                self.refresh()
            }
        })
    }

    func stop() {
        finished = true
        tasks.forEach { $0.cancel() }
        tasks = []
        sessions = []
    }

    func handle(_ fix: LocationFix) {
        position = fix
        now = max(now, fix.time)
        let before = tracker.phase
        let phase = tracker.update(fix)
        if case .left(let reason) = phase, before != phase {
            Log.drive.info("left the route (\(String(describing: reason), privacy: .public)); rerouting")
            leftRoute = true
            AudioServicesPlaySystemSound(1007)  // one chime, voice or not
            tasks.append(Task { [weak self] in await self?.reroute() })
        }
        refresh()
    }

    private func refresh() {
        screen = Guidance.screen(stage: stage, phase: tracker.phase, signalLost: tracker.signalLost(at: now),
                                 along: tracker.lastMatch?.along ?? 0, speed: position?.speed, maneuvers: maneuvers)
    }

    /// Asks Apple Maps for a route from here to the destination until it gives one, then follows
    /// that route in full.
    private func reroute() async {
        let item = MKMapItem(location: CLLocation(latitude: destination.latitude, longitude: destination.longitude), address: nil)
        while !finished && !Task.isCancelled {
            do {
                let built = try await RouteBuilder.directions(to: item)
                guard !finished else { return }
                line = built.line
                maneuvers = built.maneuvers
                tracker = RouteTracker(line: built.line, startTime: now)
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
    /// clock.
    convenience init(demo route: SavedRoute, along: Double, speed: Double, leftRoute: Bool = false, arrived: Bool = false) {
        self.init(route: route, startTime: 0)
        var t = 0.0
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
            screen = GuidanceScreen(map: .route(faint: false), banner: nil, status: .rerouting)
        }
    }
    #endif
}
