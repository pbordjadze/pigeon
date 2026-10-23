import Foundation

/// A point on the Earth in degrees (WGS 84, as Core Location and MapKit give them).
public struct GeoPoint: Sendable, Hashable, Codable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// Distances and bearings on the Earth. Great-circle distance for anything stored; a local flat
/// projection for matching a fix to a route, where segments are short and centimetres don't matter.
public enum Geo {
    /// Mean Earth radius in metres (IUGG).
    public static let earthRadius = 6_371_008.8

    /// Great-circle distance in metres (haversine).
    public static func distance(_ a: GeoPoint, _ b: GeoPoint) -> Double {
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * asin(min(1, sqrt(h)))
    }

    /// Initial bearing from `a` to `b`, in degrees clockwise from north, 0..<360.
    public static func bearing(_ a: GeoPoint, _ b: GeoPoint) -> Double {
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return normalized(atan2(y, x) * 180 / .pi)
    }

    /// The signed difference `to - from` in degrees, in -180...180 (positive: clockwise, a right turn).
    public static func turn(from: Double, to: Double) -> Double {
        var d = normalized(to - from)
        if d > 180 { d -= 360 }
        return d
    }

    static func normalized(_ degrees: Double) -> Double {
        let d = degrees.truncatingRemainder(dividingBy: 360)
        return d < 0 ? d + 360 : d
    }
}

/// Metres east and north of an origin: a flat projection good to well under a metre within a few
/// kilometres of it, which is all a route match needs.
struct LocalFrame {
    let origin: GeoPoint
    let metresPerDegreeLatitude: Double
    let metresPerDegreeLongitude: Double

    init(origin: GeoPoint) {
        self.origin = origin
        metresPerDegreeLatitude = Geo.earthRadius * .pi / 180
        metresPerDegreeLongitude = metresPerDegreeLatitude * cos(origin.latitude * .pi / 180)
    }

    func project(_ p: GeoPoint) -> (x: Double, y: Double) {
        var dLon = p.longitude - origin.longitude
        if dLon > 180 { dLon -= 360 } else if dLon < -180 { dLon += 360 }
        return (dLon * metresPerDegreeLongitude, (p.latitude - origin.latitude) * metresPerDegreeLatitude)
    }
}
