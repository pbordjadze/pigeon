import Foundation
import PigeonCore
import SwiftUI

extension Turn {
    /// The arrow the banner draws.
    var symbol: String {
        switch self {
        case .straight: "arrow.up"
        case .slightLeft: "arrow.up.left"
        case .left, .sharpLeft: "arrow.turn.up.left"
        case .slightRight: "arrow.up.right"
        case .right, .sharpRight: "arrow.turn.up.right"
        case .uTurn: "arrow.uturn.left"
        }
    }

    /// What VoiceOver says for the arrow.
    var label: String {
        switch self {
        case .straight: String(localized: "Continue straight")
        case .slightLeft: String(localized: "Bear left")
        case .left: String(localized: "Turn left")
        case .sharpLeft: String(localized: "Turn sharply left")
        case .slightRight: String(localized: "Bear right")
        case .right: String(localized: "Turn right")
        case .sharpRight: String(localized: "Turn sharply right")
        case .uTurn: String(localized: "Make a U-turn")
        }
    }
}

extension Stage {
    var title: String {
        switch self {
        case .full: String(localized: "Full Directions")
        case .landmarks: String(localized: "Landmarks")
        case .turnsOnly: String(localized: "Turns Only")
        case .quiet: String(localized: "Quiet")
        }
    }

    var symbol: String {
        switch self {
        case .full: "map.fill"
        case .landmarks: "building.2"
        case .turnsOnly: "arrow.triangle.turn.up.right.diamond"
        case .quiet: "checkmark.circle"
        }
    }
}

extension RouteProgress {
    /// "3 clean drives to go", or that the route is learned.
    var summary: String {
        if isLearned {
            return String(localized: "Learned: you don’t need Pigeon for this one")
        }
        return String(localized: "route.drivesToGo", defaultValue: "\(cleanDrivesToLearn) clean drives to go",
                      comment: "Under a route's stage: how many clean drives until the route is learned. Argument: the count.")
    }
}
