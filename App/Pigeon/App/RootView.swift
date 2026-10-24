import Foundation
import PigeonCore
import SwiftUI

/// The app's first screen: the saved routes, each at its stage. Tapping one starts a drive.
///
/// Demo scenarios (Debug builds, `ci/scenarios.txt`): `routes-empty` (and its `-dark` and
/// `-long-text` variants) with no routes saved, `routes-list` (and `-dark`) with one route at each
/// stage; the drive and arrival scenarios open a drive over the list (`DriveView`), `add-route`
/// the new route screen (`AddRouteView`).
struct RootView: View {
    @Environment(RouteStore.self) private var store
    @State private var drive: DriveSession?
    @State private var adding = false

    var body: some View {
        NavigationStack {
            List {
                if store.needsNewerApp {
                    Label("Your routes were saved by a newer version of Pigeon. Update Pigeon to see them.",
                          systemImage: "exclamationmark.arrow.circlepath")
                        .foregroundStyle(.orange)
                }
                ForEach(store.routes) { route in
                    Button { drive = DriveSession(route: route) } label: {
                        RouteRow(route: route)
                    }
                    .accessibilityHint(Text("Starts a drive on this route"))
                }
                .onDelete { offsets in
                    store.delete(Set(offsets.map { store.routes[$0].id }))
                }
            }
            .overlay {
                if store.routes.isEmpty && !store.needsNewerApp {
                    ContentUnavailableView {
                        Label("No Routes Yet", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    } description: {
                        Text("Save a route you drive often. Each time you drive it, Pigeon helps a little less, until you don’t need it.")
                    }
                }
            }
            .navigationTitle("Routes")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("New Route", systemImage: "plus") { adding = true }
                        .disabled(store.needsNewerApp)
                }
            }
            .sheet(isPresented: $adding) { AddRouteView() }
            .fullScreenCover(item: $drive) { session in
                DriveView(session: session)
            }
            #if DEBUG
            .onAppear {
                switch DemoMode.screen {
                case .drive(let session): drive = session
                case .addRoute: adding = true
                case .list: DemoMode.markReady()
                case nil: break
                }
            }
            #endif
        }
    }
}

private struct RouteRow: View {
    let route: SavedRoute

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(route.name)
                .font(.headline)
                .foregroundStyle(.primary)
            Label(route.progress.stage.title, systemImage: route.progress.stage.symbol)
                .font(.subheadline)
                .foregroundStyle(.tint)
            Text(route.progress.summary)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

extension DriveSession: Identifiable {
    var id: ObjectIdentifier { ObjectIdentifier(self) }
}
