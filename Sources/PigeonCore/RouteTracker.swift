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
/// - Off the line: a usable fix (accuracy no worse than `worstUsableAccuracy`) further than both
///   `offRouteDistance` and its own accuracy from the line counts once; `confirmations` such fixes
///   in a row are leaving the route. Only a fix within `offRouteDistance` resets the count: one
///   further off but within its own accuracy is inconclusive and changes nothing.
/// - Wrong way: `confirmations` fixes in a row more than `backtrackLimit` metres (plus the fix's
///   accuracy) back from the furthest point reached, at any speed and with or without a course
///   (only fixes within `preciseAccuracy` move that point on); or, sooner, moving faster than
///   `wrongWayMinimumSpeed` on a course more than 135° from the line's direction for
///   `wrongWayFixes` fixes in a row (a U-turn on the route). A fix with no course or speed leaves
///   that count as it was.
/// - Joining: a drive may start a little away from the line (a driveway, a parking lot). A first
///   usable fix within `joinRadius` of the line's first `joinSearch` metres waits up to
///   `joinTimeout` seconds for the driver to reach them; further away, or slower than that, is
///   leaving the route (a drive starts at the route's start).
/// - Each fix is matched only near where the last one was (`searchBehind` metres back, and ahead as
///   far as `maximumSpeed` could carry the driver since), so a route that passes the same place
///   twice, or a shortcut that rejoins it further on, can't pass for being on it.
/// - Arrived: on the line within `arrivalRadius` of its end, on a fix after the one that joined it
///   (so a very short route doesn't arrive on its first fix). `.left` and `.arrived` are final; a
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
        public var backtrackLimit = 60.0
        public var preciseAccuracy = 20.0
        public var arrivalRadius = 40.0
        /// Seconds without a usable fix (or since the start, before the first) before
        /// `signalLost(at:)` says so.
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
    /// When the drive started, on the fixes' clock.
    public let startTime: TimeInterval
    private var lastMatchTime: TimeInterval?
    private var furthestAlong = 0.0
    private var backCount = 0
    private var offCount = 0
    private var wrongWayCount = 0

    public init(line: RouteLine, startTime: TimeInterval, settings: Settings = Settings()) {
        self.line = line
        self.startTime = startTime
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
        lastUsableFixTime = fix.time
        // From the last fix that placed the driver: inconclusive fixes in between mustn't narrow
        // how far ahead they may be by now.
        let elapsed = lastMatchTime.map { fix.time - $0 } ?? 0

        let range: ClosedRange<Double>
        if let last = lastMatch {
            let lower = max(0, last.along - settings.searchBehind)
            range = lower...max(lower, last.along + settings.searchBehind + settings.maximumSpeed * elapsed)
        } else {
            range = 0...settings.joinSearch
        }
        // The course breaks a tie between two legs of the route only when it means something.
        let heading = (fix.speed ?? 0) >= settings.wrongWayMinimumSpeed ? fix.course : nil
        guard let match = line.match(fix.point, within: range, near: lastMatch?.along, heading: heading) else {
            phase = .left(.offLine)
            return phase
        }
        if phase == .joining {
            if match.offset <= settings.offRouteDistance {
                phase = .onRoute
                lastMatch = match
                lastMatchTime = fix.time
                furthestAlong = match.along
                return phase
            } else if match.offset > settings.joinRadius {
                phase = .left(.neverJoined)
                return phase
            } else if fix.time - startTime > settings.joinTimeout {
                phase = .left(.neverJoined)
                return phase
            } else {
                return phase  // still on the way to the line
            }
        }

        if match.offset > settings.offRouteDistance {
            // Off by more than the fix's own uncertainty counts; within it, the fix can't tell.
            // Neither kind moves where the driver is taken to be.
            if match.offset > fix.horizontalAccuracy {
                offCount += 1
                if offCount >= settings.confirmations {
                    phase = .left(.offLine)
                }
            }
            return phase
        }
        offCount = 0

        if furthestAlong - match.along > settings.backtrackLimit + fix.horizontalAccuracy {
            backCount += 1
            if backCount >= settings.confirmations {
                phase = .left(.wrongWay)
            }
            return phase
        }
        backCount = 0
        if let course = fix.course, let speed = fix.speed {
            if speed >= settings.wrongWayMinimumSpeed, abs(Geo.turn(from: match.bearing, to: course)) > 135 {
                wrongWayCount += 1
                if wrongWayCount >= settings.wrongWayFixes {
                    phase = .left(.wrongWay)
                    return phase
                }
            } else {
                wrongWayCount = 0
            }
        }

        lastMatch = match
        lastMatchTime = fix.time
        if fix.horizontalAccuracy <= settings.preciseAccuracy {
            furthestAlong = max(furthestAlong, match.along)
        }
        if line.length - match.along <= settings.arrivalRadius {
            phase = .arrived
        }
        return phase
    }

    /// True once the drive has gone `signalTimeout` seconds without a usable fix, or since its
    /// start before the first (a tunnel, a garage, a phone that lost the sky). The app says so
    /// rather than staying silent.
    public func signalLost(at now: TimeInterval) -> Bool {
        guard !isFinal else { return false }
        return now - (lastUsableFixTime ?? startTime) > settings.signalTimeout
    }
}
