import Foundation

/// Which way a turn goes, from the route's own geometry (so it's the same in every language).
public enum Turn: String, Sendable, Codable, CaseIterable {
    case straight, slightLeft, left, sharpLeft, slightRight, right, sharpRight, uTurn

    /// From the change of direction in degrees (positive: clockwise, to the right).
    public init(angle: Double) {
        let a = abs(angle)
        switch a {
        case ..<20: self = .straight
        case ..<45: self = angle < 0 ? .slightLeft : .slightRight
        case ..<135: self = angle < 0 ? .left : .right
        case ..<165: self = angle < 0 ? .sharpLeft : .sharpRight
        default: self = .uTurn
        }
    }

    /// A stored turn this app doesn't know reads as `straight`; the banner still shows the step.
    public init(from decoder: any Decoder) throws {
        self = Turn(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .straight
    }
}

/// A place on the route where the driver has to do something: one step of the directions it was
/// saved with.
public struct Maneuver: Sendable, Codable, Equatable {
    /// Metres along the route's line to the turn.
    public var along: Double
    public var turn: Turn
    /// The step as the directions word it ("Turn right onto Beacon St"), in the language Apple
    /// Maps gave it in.
    public var instruction: String?
    /// A place near the turn to name it by ("the Shell station"), found when the route was saved.
    public var landmark: String?

    public init(along: Double, turn: Turn, instruction: String? = nil, landmark: String? = nil) {
        self.along = along
        self.turn = turn
        self.instruction = instruction
        self.landmark = landmark
    }
}

extension RouteLine {
    /// The turn the line makes at `along`: its direction over `span` metres before against over
    /// `span` metres after.
    public func turn(at along: Double, span: Double = 30) -> Turn {
        let before = point(at: along - span), at = point(at: along), after = point(at: along + span)
        guard Geo.distance(before, at) > 1, Geo.distance(at, after) > 1 else { return .straight }
        return Turn(angle: Geo.turn(from: Geo.bearing(before, at), to: Geo.bearing(at, after)))
    }
}
