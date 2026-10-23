import Foundation

/// One location fix, as Core Location reports it.
public struct LocationFix: Sendable, Equatable {
    public var point: GeoPoint
    /// Radius of uncertainty in metres; negative means the fix has no valid position.
    public var horizontalAccuracy: Double
    /// Direction of travel, degrees clockwise from north; nil when unknown.
    public var course: Double?
    /// Metres per second; nil when unknown.
    public var speed: Double?
    /// Seconds on any clock that only moves forward (the fix's timestamp).
    public var time: TimeInterval

    public init(point: GeoPoint, horizontalAccuracy: Double, course: Double? = nil, speed: Double? = nil, time: TimeInterval) {
        self.point = point
        self.horizontalAccuracy = horizontalAccuracy
        self.course = course
        self.speed = speed
        self.time = time
    }
}

/// Follows one drive along a `RouteLine` and decides, fix by fix, whether the driver is on it.
///
/// This is the safety rule's trigger: the moment it reports `.left`, the app brings full guidance
/// back and reroutes, whatever the stage. It leans towards saying "left": a false alarm costs a
/// few seconds of extra directions; a missed one leaves a driver lost in silence.
///
/// - Off the line: a usable fix (accuracy no worse than `worstUsableAccuracy`) further than
///   `offRouteDistance` from the line, or further than its own accuracy when that is larger, counts
///   once; `confirmations` such fixes in a row are leaving the route. A fix back on the line resets
///   the count.
/// - Wrong way: moving faster than `wrongWayMinimumSpeed` on a course more than 135° from the
///   line's direction for `wrongWayFixes` fixes in a row (a U-turn on the route).
/// - Joining: a drive may start a little away from the line (a driveway, a parking lot). A first
///   usable fix within `joinRadius` of the line's first `joinSearch` metres waits up to
///   `joinTimeout` seconds for the driver to reach them; further away, or slower than that, is
///   leaving the route (a drive starts at the route's start).
/// - Each fix is matched only near where the last one was (`searchBehind` metres back, and ahead as
///   far as `maximumSpeed` could carry the driver since), so a route that passes the same place
///   twice, or a shortcut that rejoins it further on, can't pass for being on it.
/// - Arrived: on the line within `arrivalRadius` of its end. `.left` and `.arrived` are final; a
///   reroute is a new line and a new tracker.
public struct RouteTracker: Sendable {
    public struct Settings: Sendable, Equatable {
        public var offRouteDistance = 40.0
        public var confirmations = 2
        public var worstUsableAccuracy = 50.0
        public var joinRadius = 150.0
        public var joinTimeout: TimeInterval = 120
        public var joinSearch = 500.0
        public var wrongWayFixes = 3
        public var wrongWayMinimumSpeed = 5.0
        public var arrivalRadius = 40.0
        /// Seconds without a usable fix before `signalLost(at:)` says so.
        public var signalTimeout: TimeInterval = 20
        public var searchBehind = 150.0
        /// Metres per second, for how far ahead the next fix may be found (about 160 km/h).
        public var maximumSpeed = 45.0

        public init() {}
    }

    public enum Phase: Sendable, Equatable {
        /// Not yet on the line (the drive started a little away from it).
        case joining
        case onRoute
        case left(Reason)
        case arrived
    }

    public enum Reason: Sendable, Equatable {
        case offLine
        case wrongWay
        case neverJoined
    }

    public let line: RouteLine
    public let settings: Settings
    public private(set) var phase: Phase = .joining
    /// The last usable fix's place on the line.
    public private(set) var lastMatch: RouteLine.Match?
    public private(set) var lastUsableFixTime: TimeInterval?
    private var firstUsableFixTime: TimeInterval?
    private var offCount = 0
    private var wrongWayCount = 0

    public init(line: RouteLine, settings: Settings = Settings()) {
        self.line = line
        self.settings = settings
    }

    public var isFinal: Bool {
        switch phase {
        case .left, .arrived: true
        case .joining, .onRoute: false
        }
    }

    /// Takes the next fix and returns the phase after it. Fixes without a usable position change
    /// nothing (`signalLost(at:)` notices their absence).
    @discardableResult
    public mutating func update(_ fix: LocationFix) -> Phase {
        guard !isFinal, fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= settings.worstUsableAccuracy else {
            return phase
        }
        if let last = lastUsableFixTime, fix.time < last { return phase }  // out of order
        let elapsed = lastUsableFixTime.map { fix.time - $0 } ?? 0
        firstUsableFixTime = firstUsableFixTime ?? fix.time
        lastUsableFixTime = fix.time

        let range: ClosedRange<Double>
        if let last = lastMatch {
            let lower = max(0, last.along - settings.searchBehind)
            range = lower...max(lower, last.along + settings.searchBehind + settings.maximumSpeed * elapsed)
        } else {
            range = 0...settings.joinSearch
        }
        guard let match = line.match(fix.point, within: range) else {
            phase = .left(.offLine)
            return phase
        }
        let limit = max(settings.offRouteDistance, fix.horizontalAccuracy)

        if phase == .joining {
            if match.offset <= limit {
                phase = .onRoute
            } else if match.offset > settings.joinRadius {
                phase = .left(.neverJoined)
                return phase
            } else if fix.time - (firstUsableFixTime ?? fix.time) > settings.joinTimeout {
                phase = .left(.neverJoined)
                return phase
            } else {
                return phase  // still on the way to the line
            }
        }

        if match.offset > limit {
            offCount += 1
            if offCount >= settings.confirmations {
                phase = .left(.offLine)
                return phase
            }
            // An unconfirmed stray fix doesn't move where the driver is taken to be.
            return phase
        }
        offCount = 0

        if let course = fix.course, let speed = fix.speed, speed >= settings.wrongWayMinimumSpeed,
           abs(Geo.turn(from: match.bearing, to: course)) > 135 {
            wrongWayCount += 1
            if wrongWayCount >= settings.wrongWayFixes {
                phase = .left(.wrongWay)
                return phase
            }
        } else {
            wrongWayCount = 0
        }

        lastMatch = match
        if line.length - match.along <= settings.arrivalRadius {
            phase = .arrived
        }
        return phase
    }

    /// True once the drive has gone `signalTimeout` seconds without a usable fix (a tunnel, a
    /// garage, a phone that lost the sky). The app says so rather than staying silent.
    public func signalLost(at now: TimeInterval) -> Bool {
        guard !isFinal, let last = lastUsableFixTime else { return false }
        return now - last > settings.signalTimeout
    }
}
