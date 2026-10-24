import Foundation
import PigeonCore
import SwiftUI

/// After a drive, once stopped: how it went and where the route stands now.
struct ArrivalView: View {
    /// The route as the drive left it.
    let route: SavedRoute
    let outcome: RouteProgress.Outcome
    let done: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(headline, systemImage: symbol)
                            .font(.title2.bold())
                            .foregroundStyle(outcome == .leftRoute ? Color.orange : Color.accentColor)
                        Text(explanation)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                Section("Next Drive") {
                    Label(route.progress.stage.title, systemImage: route.progress.stage.symbol)
                    Text(route.progress.summary)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(route.name)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: done)
                }
            }
        }
    }

    private var headline: String {
        switch outcome {
        case .clean: String(localized: "Clean Drive")
        case .leftRoute: String(localized: "You Left the Route")
        case .unchanged: String(localized: "Drive Ended")
        }
    }

    private var symbol: String {
        switch outcome {
        case .clean: "checkmark.seal.fill"
        case .leftRoute: "arrow.uturn.backward.circle.fill"
        case .unchanged: "stop.circle"
        }
    }

    private var explanation: String {
        switch outcome {
        case .clean: String(localized: "You got there without leaving the route, so the next drive gives a little less help.")
        case .leftRoute: String(localized: "The next drive gives a little more help. Leaving the route never sends it back to the start.")
        case .unchanged: String(localized: "The drive ended before you arrived, so the route stays where it was.")
        }
    }
}
