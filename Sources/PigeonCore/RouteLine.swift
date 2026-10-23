import Foundation

/// A saved route's path: the polyline Apple Maps gave when the route was saved, kept and guided along
/// unchanged on every drive so there is one route to learn.
public struct RouteLine: Sendable, Hashable, Codable {
    public let points: [GeoPoint]
    /// Metres along the line to each point; `cumulative[0] == 0`, the last is `length`.
    public let cumulative: [Double]

    public var length: Double { cumulative.last ?? 0 }
    public var start: GeoPoint { points[0] }
    public var end: GeoPoint { points[points.count - 1] }

    /// Consecutive duplicate points are dropped. Nil for fewer than two distinct points.
    public init?(points: [GeoPoint]) {
        var kept: [GeoPoint] = []
        kept.reserveCapacity(points.count)
        for p in points where kept.last.map({ Geo.distance($0, p) > 0.01 }) ?? true {
            kept.append(p)
        }
        guard kept.count >= 2 else { return nil }
        var cumulative = [0.0]
        cumulative.reserveCapacity(kept.count)
        for i in 1..<kept.count {
            cumulative.append(cumulative[i - 1] + Geo.distance(kept[i - 1], kept[i]))
        }
        self.points = kept
        self.cumulative = cumulative
    }

    // Stored as its points alone: decoding rebuilds the distances, so a damaged file can't give a
    // line whose distances disagree with its points.
    enum CodingKeys: String, CodingKey { case points }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let points = try container.decode([GeoPoint].self, forKey: .points)
        guard let line = RouteLine(points: points) else {
            throw DecodingError.dataCorruptedError(forKey: .points, in: container, debugDescription: "A route needs two distinct points")
        }
        self = line
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(points, forKey: .points)
    }

    /// Where a point falls on the line: the nearest place on it and how far that is.
    public struct Match: Sendable, Equatable {
        /// Metres from the point to the line.
        public var offset: Double
        /// Metres along the line to the nearest place on it.
        public var along: Double
        /// The segment it falls on (`points[segment]` to `points[segment + 1]`).
        public var segment: Int
        /// The segment's direction, degrees clockwise from north.
        public var bearing: Double
    }

    /// The nearest place on the line to `p`, searching only the part of the line between `range`'s
    /// bounds (metres along; the whole line when nil). A route that passes the same spot twice (a
    /// loop, a road and the bridge over it) is told apart by searching near where the driver was.
    public func match(_ p: GeoPoint, within range: ClosedRange<Double>? = nil) -> Match? {
        let lower = range?.lowerBound ?? 0, upper = range?.upperBound ?? length
        guard lower <= length, upper >= 0 else { return nil }
        let frame = LocalFrame(origin: p)
        var best: Match?
        // The first segment ending at or after `lower`, through the last starting at or before `upper`.
        var i = firstSegment(endingAtOrAfter: lower)
        while i < points.count - 1, cumulative[i] <= upper {
            let a = frame.project(points[i]), b = frame.project(points[i + 1])
            let dx = b.x - a.x, dy = b.y - a.y
            let lengthSquared = dx * dx + dy * dy
            var t = lengthSquared > 0 ? -(a.x * dx + a.y * dy) / lengthSquared : 0
            t = min(1, max(0, t))
            let segmentLength = cumulative[i + 1] - cumulative[i]
            let along = min(upper, max(lower, cumulative[i] + t * segmentLength))
            // Clamped to the range, the place may have moved along the segment: measure to it.
            let u = segmentLength > 0 ? (along - cumulative[i]) / segmentLength : 0
            let x = a.x + u * dx, y = a.y + u * dy
            let offset = (x * x + y * y).squareRoot()
            if best.map({ offset < $0.offset }) ?? true {
                best = Match(offset: offset, along: along, segment: i, bearing: Geo.bearing(points[i], points[i + 1]))
            }
            i += 1
        }
        return best
    }

    /// The point `along` metres from the start (clamped to the line).
    public func point(at along: Double) -> GeoPoint {
        let d = min(length, max(0, along))
        let i = min(points.count - 2, firstSegment(endingAtOrAfter: d))
        let segmentLength = cumulative[i + 1] - cumulative[i]
        let t = segmentLength > 0 ? (d - cumulative[i]) / segmentLength : 0
        let a = points[i], b = points[i + 1]
        return GeoPoint(latitude: a.latitude + t * (b.latitude - a.latitude),
                        longitude: a.longitude + t * (b.longitude - a.longitude))
    }

    /// The index of the first segment whose end is at or past `along` (binary search).
    func firstSegment(endingAtOrAfter along: Double) -> Int {
        var lo = 1, hi = cumulative.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if cumulative[mid] < along { lo = mid + 1 } else { hi = mid }
        }
        return lo - 1
    }
}
