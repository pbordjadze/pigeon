import Foundation
import Testing
@testable import PigeonCore

struct RouteLineTests {
    let line = TestRoutes.northThenEast

    @Test func lengthIsTheSumOfItsLegs() {
        #expect(abs(line.length - 3000) < 1)
    }

    @Test func distanceMatchesAKnownPair() {
        // Boston to New York City Hall, about 306 km great-circle.
        let boston = GeoPoint(latitude: 42.3601, longitude: -71.0589)
        let nyc = GeoPoint(latitude: 40.7128, longitude: -74.0060)
        #expect(abs(Geo.distance(boston, nyc) - 306_000) < 2000)
    }

    @Test func bearingAndTurn() {
        let a = TestRoutes.point(east: 0, north: 0)
        #expect(abs(Geo.bearing(a, TestRoutes.point(east: 0, north: 100)) - 0) < 0.1)
        #expect(abs(Geo.bearing(a, TestRoutes.point(east: 100, north: 0)) - 90) < 0.1)
        #expect(Geo.turn(from: 350, to: 10) == 20)
        #expect(Geo.turn(from: 10, to: 350) == -20)
        #expect(Geo.turn(from: 0, to: 180) == 180)
    }

    @Test func matchFindsOffsetAndProgress() throws {
        let m = try #require(line.match(TestRoutes.point(east: 25, north: 500)))
        #expect(abs(m.offset - 25) < 0.5)
        #expect(abs(m.along - 500) < 0.5)
        #expect(m.segment == 0)
        let n = try #require(line.match(TestRoutes.point(east: 400, north: 1970)))
        #expect(abs(n.offset - 30) < 0.5)
        #expect(abs(n.along - 2400) < 0.5)
        #expect(n.segment == 1)
        #expect(abs(n.bearing - 90) < 0.1)
    }

    @Test func matchStaysInsideTheRange() throws {
        // Near the corner, but only the first kilometre may be searched.
        let m = try #require(line.match(TestRoutes.point(east: 0, north: 1990), within: 0...1000))
        #expect(abs(m.along - 1000) < 0.5)
        #expect(abs(m.offset - 990) < 1)
        #expect(line.match(TestRoutes.origin, within: 4000...5000) == nil)
    }

    @Test func pointAtIsOnTheLine() {
        let p = line.point(at: 2500)
        let expected = TestRoutes.point(east: 500, north: 2000)
        #expect(Geo.distance(p, expected) < 0.5)
        #expect(line.point(at: -10) == line.start)
        #expect(line.point(at: 10_000) == line.end)
    }

    @Test func degenerateLinesAreRejected() {
        #expect(RouteLine(points: []) == nil)
        #expect(RouteLine(points: [TestRoutes.origin, TestRoutes.origin]) == nil)
        let a = TestRoutes.origin, b = TestRoutes.point(east: 0, north: 10)
        #expect(RouteLine(points: [a, a, b, b])?.points.count == 2)
    }

    @Test func codingRebuildsDistancesAndRejectsDamage() throws {
        let data = try JSONEncoder().encode(line)
        let decoded = try JSONDecoder().decode(RouteLine.self, from: data)
        #expect(decoded == line)
        let damaged = Data(#"{"points":[{"latitude":1,"longitude":2}]}"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(RouteLine.self, from: damaged) }
    }
}
