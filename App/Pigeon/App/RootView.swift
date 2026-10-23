import SwiftUI

/// The app's first screen: the saved routes.
///
/// Demo scenarios (Debug builds, `ci/scenarios.txt`): `routes-empty`, and its `-dark` and
/// `-long-text` variants, show the list with no routes saved.
struct RootView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("No Routes Yet", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
            } description: {
                Text("Save a route you drive often. Each time you drive it, Pigeon helps a little less, until you don’t need it.")
            }
            .navigationTitle("Routes")
            #if DEBUG
            .task { DemoMode.markReady() }
            #endif
        }
    }
}
