import Foundation
@testable import PigeonCore

/// Routes and drives laid out in metres from a fixed origin (Boston Common), so tests read as maps.
enum TestRoutes {
    static let origin = GeoPoint(latitude: 42.3550, longitude: -71.0656)

    /// The point `east` and `north` metres from the origin.
    static func point(east: Double, north: Double) -> GeoPoint {
        let frame = LocalFrame(origin: origin)
        return GeoPoint(latitude: origin.latitude + north / frame.metresPerDegreeLatitude,
                        longitude: origin.longitude + east / frame.metresPerDegreeLongitude)
    }

    /// 2 km north, then right and 1 km east: 3 km with one turn.
    static let northThenEast = RouteLine(points: [
        point(east: 0, north: 0), point(east: 0, north: 2000), point(east: 1000, north: 2000),
    ])!

    /// A fix at `east`, `north` metres, at time `t`.
    static func fix(east: Double, north: Double, t: TimeInterval, accuracy: Double = 5,
                    course: Double? = nil, speed: Double? = nil) -> LocationFix {
        LocationFix(point: point(east: east, north: north), horizontalAccuracy: accuracy,
                    course: course, speed: speed, time: t)
    }

    /// Fixes every second driving `northThenEast` at `speed` m/s from `from` to `to` metres along,
    /// `sideways` metres to the right of the line.
    static func drive(from: Double, to: Double, speed: Double = 14, sideways: Double = 0, startTime: TimeInterval = 0) -> [LocationFix] {
        var fixes: [LocationFix] = []
        var along = from, t = startTime
        while along <= to {
            let (east, north, course) = along <= 2000
                ? (sideways, along, 0.0)
                : (along - 2000, 2000 - sideways, 90.0)
            fixes.append(fix(east: east, north: north, t: t, course: course, speed: speed))
            along += speed
            t += 1
        }
        return fixes
    }
}
