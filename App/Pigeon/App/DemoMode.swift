#if DEBUG
import Foundation
import os

/// Deterministic, launch-argument-driven app states for screenshots and UI tests.
///
///     xcrun simctl launch <udid> com.pbordjadze.pigeon -demo routes-empty
///
/// Scenario names are owned by the views that render them (see `RootView`). Scenarios named
/// `*-dark` are captured in dark appearance and `*-long-text` with every localized string doubled
/// (`ci/screenshots.sh`).
///
/// Debug builds only: the demo types are compiled out of Release builds, so a shipped app has no
/// launch argument that swaps its content (`ci/check_release.sh` checks).
enum DemoMode {
    /// The requested scenario, e.g. "routes-empty".
    static let scenario: String? = UserDefaults.standard.string(forKey: "demo")

    static var isActive: Bool { scenario != nil }

    /// `tmp/demo-ready` in the app's data container. CI screenshots a scenario shortly after
    /// this file appears instead of sleeping for a worst-case delay.
    static let readyMarker = FileManager.default.temporaryDirectory.appending(path: "demo-ready")

    /// Signals that the scenario's content is on screen; only animations are still settling.
    static func markReady() {
        guard isActive else { return }
        FileManager.default.createFile(atPath: readyMarker.path, contents: Data())
        Log.demo.info("demo-ready \(scenario ?? "", privacy: .public)")
    }
}
#endif
