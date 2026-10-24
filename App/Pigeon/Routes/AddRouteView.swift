import CoreLocation
import Foundation
import MapKit
import PigeonCore
import SwiftUI

/// Search for a place, and save the drive there from here as a new route at `full`.
///
/// Locked while the car moves (CLAUDE.md › Safety): setting up a route means reading and typing.
/// Demo scenario: `add-route` (the empty search).
struct AddRouteView: View {
    @Environment(RouteStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var searching = false
    @State private var building: String?
    @State private var failure: String?
    @State private var moving = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("New Route")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", role: .cancel) { dismiss() }
                    }
                }
        }
        .task { await watchMotion() }
        #if DEBUG
        .onAppear { DemoMode.markReady() }
        #endif
    }

    @ViewBuilder private var content: some View {
        if moving {
            ContentUnavailableView {
                Label("Pull Over to Add a Route", systemImage: "car.side")
            } description: {
                Text("Setting up a route waits until the car stops.")
            }
        } else if let building {
            VStack(spacing: 16) {
                ProgressView()
                Text(building)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                if let failure {
                    Text(failure)
                        .foregroundStyle(.orange)
                }
                ForEach(results, id: \.self) { item in
                    Button { save(item) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name ?? "")
                                .foregroundStyle(.primary)
                            if let address = item.address?.shortAddress {
                                Text(address)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .overlay {
                if results.isEmpty && !searching {
                    ContentUnavailableView {
                        Label("Where To?", systemImage: "magnifyingglass")
                    } description: {
                        Text("Search for a place you drive to often. Pigeon saves the route from here.")
                    }
                } else if searching {
                    ProgressView()
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Search for a place"))
            .onSubmit(of: .search) { Task { await search() } }
        }
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        searching = true
        failure = nil
        defer { searching = false }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.resultTypes = [.pointOfInterest, .address]
        do {
            results = try await MKLocalSearch(request: request).start().mapItems
        } catch {
            results = []
            failure = String(localized: "error.search", defaultValue: "No places found for “\(text)”.",
                             comment: "Shown when a destination search finds nothing. Argument: what was searched for.")
        }
    }

    private func save(_ item: MKMapItem) {
        Task {
            building = String(localized: "Finding the route…")
            defer { building = nil }
            do {
                let directions = try await RouteBuilder.directions(to: item)
                building = String(localized: "Naming the turns…")
                let maneuvers = await RouteBuilder.addingLandmarks(to: directions.maneuvers, on: directions.line)
                let name = item.name ?? String(localized: "Route")
                store.add(SavedRoute(name: name, line: directions.line, maneuvers: maneuvers, savedAt: Date()))
                dismiss()
            } catch {
                failure = error.localizedDescription
            }
        }
    }

    /// Keeps `moving` current while this screen is open.
    private func watchMotion() async {
        #if DEBUG
        if DemoMode.isActive { return }  // no permission prompt over a screenshot
        #endif
        let session = CLServiceSession(authorization: .whenInUse)
        defer { withExtendedLifetime(session) {} }
        do {
            for try await update in CLLocationUpdate.liveUpdates(.automotiveNavigation) {
                moving = (update.location?.speed ?? 0) > 3
            }
        } catch {
            moving = false
        }
    }
}
