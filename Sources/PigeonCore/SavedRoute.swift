import Foundation

/// A route the driver saved: the path to learn, its turns, and how far along learning it they are.
public struct SavedRoute: Sendable, Codable, Identifiable, Equatable {
    public var id: UUID
    /// What the route list calls it (the destination's name, unless the driver renames it).
    public var name: String
    public var line: RouteLine
    public var maneuvers: [Maneuver]
    public var progress: RouteProgress
    public var savedAt: Date
    public var lastDriven: Date?

    public init(id: UUID = UUID(), name: String, line: RouteLine, maneuvers: [Maneuver],
                progress: RouteProgress = RouteProgress(), savedAt: Date, lastDriven: Date? = nil) {
        self.id = id
        self.name = name
        self.line = line
        self.maneuvers = maneuvers.sorted { $0.along < $1.along }
        self.progress = progress
        self.savedAt = savedAt
        self.lastDriven = lastDriven
    }

    /// Records a finished drive: moves the route's stage by its outcome.
    public mutating func recordDrive(_ outcome: RouteProgress.Outcome, at date: Date) {
        progress.record(outcome)
        lastDriven = date
    }
}

/// The file the app keeps its routes in: a version, so a newer app's file is recognized, and the
/// routes.
public struct RouteFile: Sendable, Codable, Equatable {
    public static let currentVersion = 1

    public var version: Int
    public var routes: [SavedRoute]

    public init(routes: [SavedRoute]) {
        version = Self.currentVersion
        self.routes = routes
    }

    public enum ReadError: Error, Equatable {
        /// Written by a newer app: keep it as it is and say an update is needed.
        case newerVersion(Int)
    }

    public static func read(_ data: Data) throws -> RouteFile {
        struct Header: Decodable { var version: Int }
        let header = try JSONDecoder().decode(Header.self, from: data)
        guard header.version <= currentVersion else { throw ReadError.newerVersion(header.version) }
        return try JSONDecoder().decode(RouteFile.self, from: data)
    }

    public func write() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .deferredToDate
        return try encoder.encode(self)
    }
}
