import SwiftUI

@main
struct PigeonApp: App {
    @State private var store = RouteStore.forLaunch()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
        }
    }
}
