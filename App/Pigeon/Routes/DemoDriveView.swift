import CoreLocation
import Foundation
import os
import PigeonCore
import SwiftUI

/// Sets up a demo drive: Pigeon drives a made-up route by itself (`SampleRoute`, at about four
/// times speed), so every stage, leaving the route and the arrival summary can be seen without
/// driving. Locked while the car moves, like the new route screen.
///
/// Demo scenario: `demo-setup`.
struct DemoDriveView: View {
    @Environment(\.dismiss) private var dismiss
    let start: (DriveSession) -> Void
    @State private var stage = Stage.full
    @State private var wrongTurn = false
    @State private var motion = Motion()

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                if motion.isMoving(at: context.date.timeIntervalSinceReferenceDate) {
                    ContentUnavailableView {
                        Label("Pull Over to Try the Demo", systemImage: "car.side")
                    } description: {
                        Text("The demo waits until the car stops.")
                    }
                } else {
                    form
                }
            }
            .navigationTitle("Demo Drive")
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

    private var form: some View {
        Form {
            Section {
                Text("Pigeon drives a made-up route around Boston Common by itself, about four times faster than real, so you can see what each stage shows.")
                    .foregroundStyle(.secondary)
            }
            Section("Stage") {
                Picker("Stage", selection: $stage) {
                    ForEach(Stage.allCases, id: \.self) { stage in
                        Label(stage.title, systemImage: stage.symbol).tag(stage)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Section {
                Toggle("Take a wrong turn", isOn: $wrongTurn)
            } footer: {
                Text("Partway along, the demo turns off the route: the off-route notice shows, a new route is found, and full directions come back for the rest of the drive.")
            }
            Section {
                Button("Start Demo Drive", systemImage: "play.fill") {
                    start(DriveSession.demo(stage: stage, wrongTurn: wrongTurn))
                    dismiss()
                }
                .bold()
            }
        }
    }

    /// Keeps `motion` current while this screen is open.
    private func watchMotion() async {
        #if DEBUG
        if DemoMode.isActive { return }  // no permission prompt over a screenshot
        #endif
        let session = CLServiceSession(authorization: .whenInUse)
        defer { withExtendedLifetime(session) {} }
        do {
            for try await update in CLLocationUpdate.liveUpdates(.automotiveNavigation) {
                if update.stationary { motion.stopped(at: Date().timeIntervalSinceReferenceDate) }
                if let location = update.location { motion.update(LocationFix(location)) }
            }
        } catch {
            Log.drive.error("location updates ended: \(error.localizedDescription, privacy: .public)")
        }
    }
}
