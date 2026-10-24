import Foundation

/// What the drive screen shows at a moment: the one place the stages' fading is decided, so the
/// phone's screen and (later) CarPlay's show the same thing.
public struct GuidanceScreen: Sendable, Equatable {
    public enum Map: Sendable, Equatable {
        /// The map following the car, the route drawn on it.
        case route(faint: Bool)
        /// The map following the car, no route on it.
        case roadsOnly
        /// No map.
        case hidden
    }

    public enum Status: Sendable, Equatable {
        case onRoute
        /// The drive began away from the route; the driver is on the way to it.
        case joining
        /// The driver left the route: full guidance is back while a new route is found.
        case rerouting
        /// No usable location for a while.
        case signalLost
        case arrived
    }

    public struct Banner: Sendable, Equatable {
        public var turn: Turn
        /// Metres to the turn, shown only at `full`.
        public var distance: Double?
        public var instruction: String?
        public var landmark: String?

        public init(turn: Turn, distance: Double?, instruction: String?, landmark: String?) {
            self.turn = turn
            self.distance = distance
            self.instruction = instruction
            self.landmark = landmark
        }
    }

    public var map: Map
    public var banner: Banner?
    public var status: Status

    public init(map: Map, banner: Banner?, status: Status) {
        self.map = map
        self.banner = banner
        self.status = status
    }
}

/// Decides what the drive screen shows from the route's stage and where the driver is.
///
/// - `full`: the route drawn, the next turn with its distance and instruction.
/// - `landmarks`: the route faint, the next turn by its landmark (its instruction when none was found),
///   no distance.
/// - `turnsOnly`: the roads without the route; the next turn's arrow alone, only from
///   `cueSeconds` before it at the current speed (never less than `cueMinimumDistance`), early
///   enough to change lanes.
/// - `quiet`: no map, no banner.
/// Whatever the stage, joining the route, losing the signal and leaving the route show the route
/// in full: the help comes back when the driver might need it.
public enum Guidance {
    public static let cueSeconds = 15.0
    public static let cueMinimumDistance = 150.0
    /// A turn this close behind the driver has been made: the next one is shown.
    static let passedTurn = 10.0

    public static func screen(stage: Stage, phase: RouteTracker.Phase, signalLost: Bool,
                              along: Double, speed: Double?, maneuvers: [Maneuver]) -> GuidanceScreen {
        switch phase {
        case .arrived:
            return GuidanceScreen(map: .hidden, banner: nil, status: .arrived)
        case .left:
            return GuidanceScreen(map: .route(faint: false), banner: nil, status: .rerouting)
        case .joining:
            return GuidanceScreen(map: .route(faint: false), banner: nil, status: .joining)
        case .onRoute:
            break
        }
        let next = maneuvers.first { $0.along > along - passedTurn }
        let full = next.map {
            GuidanceScreen.Banner(turn: $0.turn, distance: max(0, $0.along - along), instruction: $0.instruction, landmark: nil)
        }
        if signalLost {
            return GuidanceScreen(map: .route(faint: false), banner: full, status: .signalLost)
        }
        switch stage {
        case .full:
            return GuidanceScreen(map: .route(faint: false), banner: full, status: .onRoute)
        case .landmarks:
            let banner = next.map {
                GuidanceScreen.Banner(turn: $0.turn, distance: nil, instruction: $0.landmark == nil ? $0.instruction : nil, landmark: $0.landmark)
            }
            return GuidanceScreen(map: .route(faint: true), banner: banner, status: .onRoute)
        case .turnsOnly:
            var banner: GuidanceScreen.Banner?
            if let next {
                let reach = max(cueMinimumDistance, cueSeconds * (speed ?? 0))
                if next.along - along <= reach {
                    banner = GuidanceScreen.Banner(turn: next.turn, distance: nil, instruction: nil, landmark: nil)
                }
            }
            return GuidanceScreen(map: .roadsOnly, banner: banner, status: .onRoute)
        case .quiet:
            return GuidanceScreen(map: .hidden, banner: nil, status: .onRoute)
        }
    }
}
