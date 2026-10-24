import Foundation

/// Whether the car is moving, for the rule that nothing needing reading or touching is offered
/// while it does (CLAUDE.md › Safety).
///
/// Leans towards "moving":
/// - A fix without a speed (Core Location drops it on loose fixes and in urban canyons) takes the
///   speed from the oldest fix of the last `window` seconds, counting only the distance beyond the
///   two fixes' accuracy: a parked phone's jitter indoors doesn't read as driving, and a moving car
///   soon outruns the uncertainty. Such a guess says "moving" on its own, but "stopped" only when
///   it spans at least `stillSpan` seconds and comes out under half the threshold; a reported
///   speed, or Core Location saying the device is stationary (`stopped(at:)`), says either.
/// - The car counts as moving until `settle` seconds after the last reading above `threshold`, so a
///   red light doesn't unlock the screen at once.
/// - With no fixes at all (a tunnel, location stopped), the last reading stands: a car last seen
///   moving counts as moving for up to `unknownLimit` seconds after its last fix.
public struct Motion: Sendable, Equatable {
    public var threshold = 2.5
    public var settle: TimeInterval = 10
    public var unknownLimit: TimeInterval = 120
    public var window: TimeInterval = 20
    public var stillSpan: TimeInterval = 15
    private var recent: [LocationFix] = []
    private var last: LocationFix? { recent.last }
    private var lastMovingTime: TimeInterval?
    private var lastReadingMoving = false

    public init() {}

    public mutating func update(_ fix: LocationFix) {
        if let last, fix.time < last.time { return }
        defer {
            recent.append(fix)
            recent.removeAll { fix.time - $0.time > window }
        }
        if let speed = fix.speed {
            lastReadingMoving = speed > threshold
        } else if let anchor = recent.first, fix.time > anchor.time {
            let uncertainty = max(0, anchor.horizontalAccuracy) + max(0, fix.horizontalAccuracy)
            let guess = max(0, Geo.distance(anchor.point, fix.point) - uncertainty) / (fix.time - anchor.time)
            if guess > threshold {
                lastReadingMoving = true
            } else if fix.time - anchor.time >= stillSpan && guess < threshold / 2 {
                lastReadingMoving = false
            } else {
                return
            }
        } else {
            return
        }
        if lastReadingMoving {
            lastMovingTime = max(lastMovingTime ?? fix.time, fix.time)
        }
    }

    /// Core Location reported the device stationary: a reading of "stopped".
    public mutating func stopped(at time: TimeInterval) {
        lastReadingMoving = false
        if let t = lastMovingTime, t > time - settle { lastMovingTime = time - settle }
    }

    public func isMoving(at now: TimeInterval) -> Bool {
        guard let movingTime = lastMovingTime else { return false }
        if now - movingTime < settle { return true }
        // No fix for a while after a moving reading: unknown, so moving, for a limited time.
        if lastReadingMoving, let last, now - last.time >= settle, now - last.time < unknownLimit { return true }
        return false
    }
}
