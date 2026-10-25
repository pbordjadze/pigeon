import CoreLocation
import Foundation
import MapKit
import os
import PigeonCore
import SwiftUI
import UIKit

/// The screen during a drive: one glanceable thing at a time, nothing to read closely or touch
/// while the car moves (CLAUDE.md › Safety). What it shows comes from `GuidanceScreen`.
///
/// The drive ends itself on arrival (`DriveSession.finish`), screen on or off; this view only
/// shows it.
///
/// Demo scenarios (Debug builds): `drive-full`, `drive-landmarks`, `drive-turns`, `drive-quiet`
/// (and `drive-quiet-dark`, `drive-full-long-text`), `drive-rerouting`, `arrival-clean`.
struct DriveView: View {
    @Environment(\.dismiss) private var dismiss
    @State var session: DriveSession
    @State private var camera: MapCameraPosition = .automatic

    var body: some View {
        ZStack(alignment: .top) {
            if let outcome = session.outcome {
                // The summary is for reading: it waits until the car has stopped.
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    if session.isMoving(at: context.date) {
                        ArrivedView(name: session.name)
                    } else if let result = session.result {
                        ArrivalView(route: result, outcome: outcome) { dismiss() }
                    } else {
                        // The route is gone from the list (deleted meanwhile): nothing to show but the way out.
                        ContentUnavailableView {
                            Label("Drive Ended", systemImage: "stop.circle")
                        } actions: {
                            Button("Done") { dismiss() }
                        }
                    }
                }
            } else {
                guidance
            }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            follow()
            #if DEBUG
            if DemoMode.isActive && !session.isDemo {  // a frozen screenshot drive
                DemoMode.markReady()
                return
            }
            #endif
            session.start()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            session.stop()
        }
        .onChange(of: session.position) { follow() }
    }

    @ViewBuilder private var guidance: some View {
        let screen = session.screen
        VStack(spacing: 0) {
            if let banner = screen.banner {
                BannerView(banner: banner)
            }
            notice(screen.status)
            switch screen.map {
            case .route(let faint):
                map(routeOpacity: faint ? 0.35 : 1)
            case .roadsOnly:
                map(routeOpacity: 0)
            case .hidden:
                QuietView(name: session.name)
            }
        }
        .overlay(alignment: .bottom) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                if session.isDemo {
                    // A simulated drive: the phone isn't the one moving.
                    Button("Stop Demo", systemImage: "stop.fill") { dismiss() }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                        .padding()
                } else if !session.isMoving(at: context.date) {
                    Button("End Drive", role: .destructive) { session.finish() }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                        .padding()
                }
            }
        }
    }

    @ViewBuilder private func notice(_ status: GuidanceScreen.Status) -> some View {
        switch status {
        case .rerouting:
            NoticeView(symbol: "exclamationmark.triangle.fill", text: Text("Off route: finding a new route"), tint: .orange)
        case .signalLost:
            NoticeView(symbol: "location.slash.fill", text: Text("No GPS signal: showing the whole route"), tint: .orange)
        case .joining:
            NoticeView(symbol: "car.fill", text: Text("Head to the start of the route"), tint: .accentColor)
        case .onRoute, .arrived:
            EmptyView()
        }
    }

    private func map(routeOpacity: Double) -> some View {
        Map(position: $camera, interactionModes: []) {
            if routeOpacity > 0 {
                MapPolyline(coordinates: session.line.points.map(\.coordinate))
                    .stroke(Color.accentColor.opacity(routeOpacity), lineWidth: 8)
            }
            if let p = session.position?.point {
                Annotation("Your position", coordinate: p.coordinate, anchor: .center) {
                    Image(systemName: "location.north.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(.white, Color.accentColor)
                        .rotationEffect(.degrees(session.position?.course ?? 0))
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(emphasis: .muted, pointsOfInterest: session.stage == .landmarks ? .all : .excludingAll))
        .mapControlVisibility(.hidden)
        .accessibilityHidden(true)
    }

    private func follow() {
        let center = session.position?.point ?? session.line.start
        camera = .camera(MapCamera(centerCoordinate: center.coordinate, distance: 900,
                                   heading: session.position?.course ?? 0, pitch: 40))
    }
}

/// The next turn, large enough to read at a glance.
private struct BannerView: View {
    let banner: GuidanceScreen.Banner

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: banner.turn.symbol)
                .font(.system(size: 52, weight: .bold))
                .accessibilityLabel(banner.turn.label)
            VStack(alignment: .leading, spacing: 4) {
                if let distance = banner.distance {
                    Text(Measurement(value: distance, unit: UnitLength.meters)
                        .formatted(.measurement(width: .abbreviated, usage: .road)))
                        .font(.largeTitle.bold())
                        .monospacedDigit()
                }
                if let landmark = banner.landmark {
                    Text(String(localized: "banner.landmark", defaultValue: "By \(landmark)",
                                comment: "Names the next turn by a place beside it. Argument: the place's name."))
                        .font(.title.bold())
                } else if let instruction = banner.instruction {
                    Text(instruction)
                        .font(banner.distance == nil ? .title2.bold() : .title3)
                }
            }
            .lineLimit(2)
            .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color.accentColor.gradient)
        .accessibilityElement(children: .combine)
    }
}

private struct NoticeView: View {
    let symbol: String
    let text: Text
    let tint: Color

    var body: some View {
        Label { text } icon: { Image(systemName: symbol) }
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.vertical, 12)
            .padding(.horizontal)
            .frame(maxWidth: .infinity)
            .background(tint.gradient)
    }
}

/// Arrived, still rolling: one word until the car stops.
private struct ArrivedView: View {
    let name: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "flag.checkered")
                .font(.system(size: 96, weight: .light))
                .foregroundStyle(.tint)
            Text("Arrived")
                .font(.largeTitle.bold())
            Text(name)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// `quiet`: no map, only that all is well.
private struct QuietView: View {
    let name: String

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.system(size: 96, weight: .light))
                .foregroundStyle(.tint)
            Text("On Route")
                .font(.largeTitle.bold())
            Text(name)
                .font(.title3)
                .foregroundStyle(.secondary)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}
