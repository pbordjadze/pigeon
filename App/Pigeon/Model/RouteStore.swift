import Foundation
import Observation
import os
import PigeonCore

/// The saved routes, kept in one file on the device (`RouteFile`, in Application Support).
///
/// A file this app can't read is never overwritten: one from a newer app stays as it is and the
/// list says an update is needed; a damaged one is moved aside (`routes.damaged-<time>.json`) before
/// a fresh list starts, so nothing the driver saved is lost to a bug.
@Observable
final class RouteStore {
    private(set) var routes: [SavedRoute] = []
    /// Set when the file was written by a newer app: the list shows it and saves nothing.
    private(set) var needsNewerApp = false
    private let url: URL?

    /// The store the app uses: the file in Application Support (an empty store in memory for demo
    /// launches, which seed their own).
    static func forLaunch() -> RouteStore {
        #if DEBUG
        if let routes = DemoMode.routes { return RouteStore(routes: routes) }
        #endif
        let folder = URL.applicationSupportDirectory
        return RouteStore(url: folder.appending(path: "routes.json"))
    }

    init(url: URL) {
        self.url = url
        load()
    }

    /// In memory only (previews, demos, tests).
    init(routes: [SavedRoute]) {
        url = nil
        self.routes = routes
    }

    func route(_ id: SavedRoute.ID) -> SavedRoute? { routes.first { $0.id == id } }

    func add(_ route: SavedRoute) {
        routes.insert(route, at: 0)
        save()
    }

    func update(_ route: SavedRoute) {
        guard let i = routes.firstIndex(where: { $0.id == route.id }) else { return }
        routes[i] = route
        save()
    }

    func delete(_ ids: Set<SavedRoute.ID>) {
        routes.removeAll { ids.contains($0.id) }
        save()
    }

    private func load() {
        guard let url, let data = try? Data(contentsOf: url) else { return }
        do {
            routes = try RouteFile.read(data).routes
        } catch RouteFile.ReadError.newerVersion {
            needsNewerApp = true
        } catch {
            Log.store.error("routes.json unreadable, moved aside: \(error.localizedDescription, privacy: .public)")
            let aside = url.deletingLastPathComponent()
                .appending(path: "routes.damaged-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: url, to: aside)
        }
    }

    private func save() {
        guard let url, !needsNewerApp else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            // Readable while the phone is locked during a drive, once it has been unlocked since
            // starting up: a drive that ends with the screen off still records its outcome.
            try RouteFile(routes: routes).write()
                .write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            Log.store.error("routes.json not saved: \(error.localizedDescription, privacy: .public)")
        }
    }
}
