import Foundation

/// How much help a route gives: each clean drive moves it a stage on, each drive that leaves the
/// route moves it a stage back. A new route starts at `full`.
public enum Stage: Int, Sendable, Codable, CaseIterable, Comparable {
    /// The map with the route drawn, the next turn with its distance and instruction.
    case full = 0
    /// The map with the route faint, the next turn named by a landmark near it, no distances.
    case landmarks = 1
    /// The roads without the route, and an arrow only as a turn comes up.
    case turnsOnly = 2
    /// No map: "On route" and where you're headed.
    case quiet = 3

    public static func < (a: Stage, b: Stage) -> Bool { a.rawValue < b.rawValue }

    /// A stage stored by a newer app that this one doesn't know reads as `full`: more help, never
    /// less.
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(Int.self)
        self = Stage(rawValue: raw) ?? .full
    }

    var next: Stage { Stage(rawValue: rawValue + 1) ?? .quiet }
    var previous: Stage { Stage(rawValue: rawValue - 1) ?? .full }
}

/// One route's place on the way to not needing Pigeon, and the rule that moves it.
///
/// - A clean drive (arrived without leaving the route) moves the route up a stage; at `quiet` it
///   counts towards `quietDrivesToLearn`, after which the route is learned.
/// - A drive that left the route moves it down one stage (not back to the start) and starts the
///   count at `quiet` again.
/// - A drive that ended before arriving without leaving the route changes nothing, and neither
///   does a drive the driver says still needed the screen.
public struct RouteProgress: Sendable, Codable, Equatable {
    public static let quietDrivesToLearn = 2

    public private(set) var stage: Stage
    /// Clean drives at `quiet` since the route last reached it.
    public private(set) var quietCleanDrives: Int

    public init(stage: Stage = .full, quietCleanDrives: Int = 0) {
        self.stage = stage
        self.quietCleanDrives = stage == .quiet ? max(0, quietCleanDrives) : 0
    }

    // Decoded through `init`, so a damaged file can't hold a count at a stage that has none.
    enum CodingKeys: String, CodingKey { case stage, quietCleanDrives }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(stage: try c.decode(Stage.self, forKey: .stage),
                  quietCleanDrives: try c.decodeIfPresent(Int.self, forKey: .quietCleanDrives) ?? 0)
    }

    public var isLearned: Bool { stage == .quiet && quietCleanDrives >= Self.quietDrivesToLearn }

    /// Clean drives still needed at `quiet` before the route is learned (0 once it is; at another
    /// stage, the stages to go plus those).
    public var cleanDrivesToLearn: Int {
        let stagesToGo = Stage.quiet.rawValue - stage.rawValue
        return stagesToGo + max(0, Self.quietDrivesToLearn - quietCleanDrives)
    }

    public enum Outcome: Sendable, Equatable {
        case clean
        case leftRoute
        /// Ended before arriving without leaving the route, or the driver said they still needed
        /// the screen: no change.
        case unchanged
    }

    public mutating func record(_ outcome: Outcome) {
        switch outcome {
        case .clean:
            if stage == .quiet {
                quietCleanDrives += 1
            } else {
                stage = stage.next
            }
        case .leftRoute:
            stage = stage.previous
            quietCleanDrives = 0
        case .unchanged:
            break
        }
    }
}
