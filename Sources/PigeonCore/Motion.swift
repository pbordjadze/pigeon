import Foundation

/// Whether the car is moving, for the rule that nothing needing reading or touching is offered
/// while it does (CLAUDE.md › Safety).
///
/// Leans towards "moving": a fix without a speed (Core Location drops it on loose fixes and in
/// urban canyons) takes the speed between it and the fix before; one with neither counts as
/// nothing new. The car counts as moving until `settle` seconds after the last reading above
/// `threshold`, so a red light doesn't unlock the screen at once and losing the readings
/// doesn't either until that time has passed.
public struct Motion: Sendable, Equatable {
    public var threshold = 2.5
    public var settle: TimeInterval = 10
    private var last: LocationFix?
    private var lastMovingTime: TimeInterval?

    public init() {}

    public mutating func update(_ fix: LocationFix) {
        defer { last = fix }
        var speed = fix.speed
        if speed == nil, let last, fix.time > last.time, fix.time - last.time <= 10 {
            speed = Geo.distance(last.point, fix.point) / (fix.time - last.time)
        }
        if let speed, speed > threshold {
            lastMovingTime = max(lastMovingTime ?? fix.time, fix.time)
        }
    }

    public func isMoving(at now: TimeInterval) -> Bool {
        guard let t = lastMovingTime else { return false }
        return now - t < settle
    }
}
