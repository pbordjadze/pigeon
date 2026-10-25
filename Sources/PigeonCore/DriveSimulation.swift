import Foundation

/// A made-up route around Boston Common, laid out in metres east and north of the Common: the demo
/// drive's route and the demo screenshots'. It names public streets and places, and is no one's
/// real drive.
public enum SampleRoute {
    public static let origin = GeoPoint(latitude: 42.3550, longitude: -71.0656)

    public static func point(east: Double, north: Double) -> GeoPoint {
        let north = Geo.offset(origin, bearing: 0, distance: north)
        return Geo.offset(north, bearing: 90, distance: east)
    }

    /// 1.2 km north, right, 900 m, left, 900 m, right, 600 m: 3.6 km with three turns.
    public static let line = RouteLine(points: [
        point(east: 0, north: 0), point(east: 0, north: 1200), point(east: 900, north: 1200),
        point(east: 900, north: 2100), point(east: 1500, north: 2100),
    ])!

    public static let maneuvers = [
        Maneuver(along: 1200, turn: .right, instruction: "Turn right onto Charles Street", landmark: "Public Garden"),
        Maneuver(along: 2100, turn: .left, instruction: "Turn left onto Beacon Street"),
        Maneuver(along: 3000, turn: .right, instruction: "Turn right onto Park Street", landmark: "State House"),
    ]

    /// A route from `here` to the sample route's end: along `here`'s latitude to the end's
    /// longitude, then to the end. What the demo drive gets when it leaves the route.
    public static func reroute(from here: GeoPoint) -> (line: RouteLine, maneuvers: [Maneuver])? {
        let end = line.end
        let corner = GeoPoint(latitude: here.latitude, longitude: end.longitude)
        guard let reroute = RouteLine(points: [here, corner, end]) else { return nil }
        let turnAt = Geo.distance(here, corner)
        let maneuvers = turnAt > 30 && turnAt < reroute.length - 30
            ? [Maneuver(along: turnAt, turn: reroute.turn(at: turnAt))] : []
        return (reroute, maneuvers)
    }
}

/// A drive that drives itself, fix by fix: along the route at `speed`, `step` metres per fix (more
/// than `speed` m/s when played faster than real time), optionally taking a wrong turn at
/// `wrongTurnAt` metres (`offRouteFixes` fixes off to the right), then following whatever line
/// the drive is on now (a reroute) to its end, where it stops.
public struct DriveSimulation: Sendable {
    public let speed: Double
    public let step: Double
    public var offRouteFixes = 12

    private var line: RouteLine
    private var along = 0.0
    private var wrongTurnAt: Double?
    private var offRouteLeft = 0
    private var offBearing = 0.0
    private var last: GeoPoint
    private var stopped = 0

    public init(line: RouteLine, speed: Double = 14, step: Double = 56, wrongTurnAt: Double? = nil) {
        self.line = line
        self.speed = speed
        self.step = step
        self.wrongTurnAt = wrongTurnAt
        last = line.start
    }

    /// Whether the drive has stopped at the end.
    public var isFinished: Bool { stopped >= 3 }

    /// The next fix at `time`, given the line the drive now follows (the route, or a reroute);
    /// nil once finished. At the end come three fixes standing still.
    public mutating func next(following current: RouteLine, at time: TimeInterval) -> LocationFix? {
        guard !isFinished else { return nil }
        if let turnAt = wrongTurnAt, along >= turnAt {
            wrongTurnAt = nil
            offRouteLeft = offRouteFixes
            offBearing = (line.match(last)?.bearing ?? 0) + 90
        }
        if offRouteLeft > 0 {
            offRouteLeft -= 1
            last = Geo.offset(last, bearing: offBearing, distance: step)
            return LocationFix(point: last, horizontalAccuracy: 5, course: Geo.normalized(offBearing), speed: speed, time: time)
        }
        if current != line {
            // A new route: pick it up where the car is.
            line = current
            along = current.match(last)?.along ?? 0
        }
        if along >= line.length {
            stopped += 1
            last = line.end
            return LocationFix(point: last, horizontalAccuracy: 5, speed: 0, time: time)
        }
        along = min(line.length, along + step)
        let previous = last
        last = line.point(at: along)
        let course = Geo.distance(previous, last) > 1 ? Geo.bearing(previous, last) : nil
        return LocationFix(point: last, horizontalAccuracy: 5, course: course, speed: speed, time: time)
    }
}
