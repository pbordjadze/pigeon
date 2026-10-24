import CoreLocation
import Foundation
import MapKit
import os
import PigeonCore

/// Turns Apple Maps' directions into a route Pigeon can keep: its line, its turns, and a landmark
/// near each turn. Everything Apple Maps is asked is listed in PRIVACY.md.
enum RouteBuilder {
    nonisolated enum BuildError: LocalizedError {
        case noRoute

        var errorDescription: String? {
            String(localized: "error.noRoute", defaultValue: "Apple Maps found no driving route there.",
                   comment: "Error when no driving directions exist to the chosen place.")
        }
    }

    /// Driving directions from here to `destination`.
    static func directions(to destination: MKMapItem) async throws -> (line: RouteLine, maneuvers: [Maneuver]) {
        let request = MKDirections.Request()
        request.source = MKMapItem.forCurrentLocation()
        request.destination = destination
        request.transportType = .automobile
        request.requestsAlternateRoutes = false
        let response = try await MKDirections(request: request).calculate()
        guard let route = response.routes.first, let built = convert(route) else { throw BuildError.noRoute }
        return built
    }

    /// The line and turns of one of Apple Maps' routes. Each step's turn is where the step begins:
    /// its distance along the route, refined by matching the step's first point to the line.
    static func convert(_ route: MKRoute) -> (line: RouteLine, maneuvers: [Maneuver])? {
        guard let line = RouteLine(points: coordinates(of: route.polyline).map(GeoPoint.init)) else { return nil }
        var maneuvers: [Maneuver] = []
        var stepStart = 0.0
        for step in route.steps {
            defer { stepStart += step.distance }
            let instruction = step.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !instruction.isEmpty, stepStart > 0 else { continue }  // "Proceed to the route"
            let first = coordinates(of: step.polyline).first.map(GeoPoint.init)
            let along = first.flatMap { line.match($0, within: max(0, stepStart - 150)...(stepStart + 150))?.along } ?? stepStart
            maneuvers.append(Maneuver(along: along, turn: line.turn(at: along), instruction: instruction))
        }
        return (line, maneuvers)
    }

    /// Kinds of places a driver can see from the road and name.
    static let landmarkKinds: [MKPointOfInterestCategory] = [
        .gasStation, .school, .university, .hospital, .library, .park, .museum, .stadium, .police,
        .fireStation, .postOffice, .pharmacy, .bank, .cafe, .restaurant, .store, .theater, .hotel,
    ]

    /// Names each turn by the nearest such place within `radius` metres, asking Apple Maps once per
    /// turn (at most `limit` turns; the rest keep their instruction). A turn whose search fails
    /// keeps no landmark.
    static func addingLandmarks(to maneuvers: [Maneuver], on line: RouteLine, radius: Double = 80,
                                limit: Int = 25) async -> [Maneuver] {
        var named = maneuvers
        for i in named.indices.prefix(limit) where named[i].turn != .straight {
            let p = line.point(at: named[i].along)
            let center = CLLocationCoordinate2D(latitude: p.latitude, longitude: p.longitude)
            let request = MKLocalPointsOfInterestRequest(center: center, radius: radius)
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: landmarkKinds)
            do {
                let items = try await MKLocalSearch(request: request).start().mapItems
                let turn = CLLocation(latitude: p.latitude, longitude: p.longitude)
                named[i].landmark = items
                    .filter { !($0.name ?? "").isEmpty }
                    .min { $0.location.distance(from: turn) < $1.location.distance(from: turn) }?
                    .name
            } catch {
                Log.maps.info("no landmark for a turn: \(error.localizedDescription, privacy: .public)")
            }
        }
        return named
    }

    private static func coordinates(of polyline: MKPolyline) -> [CLLocationCoordinate2D] {
        let points = polyline.points()
        return (0..<polyline.pointCount).map { points[$0].coordinate }
    }
}

extension GeoPoint {
    init(_ c: CLLocationCoordinate2D) {
        self.init(latitude: c.latitude, longitude: c.longitude)
    }

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

extension LocationFix {
    /// A fix from Core Location, its invalid course and speed (negative) as nil.
    init(_ location: CLLocation) {
        self.init(point: GeoPoint(location.coordinate),
                  horizontalAccuracy: location.horizontalAccuracy,
                  course: location.course >= 0 ? location.course : nil,
                  speed: location.speed >= 0 ? location.speed : nil,
                  time: location.timestamp.timeIntervalSinceReferenceDate)
    }
}
