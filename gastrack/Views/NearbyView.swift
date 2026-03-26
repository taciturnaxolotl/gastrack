import SwiftUI
import CoreLocation

struct NearbyView: View {
    @StateObject private var location = LocationManager.shared
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var store: StationStore

    @State private var isRefreshing = false
    @State private var error: String?

    private let radiusKm = 16.0

    private var stations: [Station] {
        guard let coord = location.location?.coordinate else { return [] }
        return store.stations(near: coord, radiusKm: radiusKm)
    }

    var body: some View {
        NavigationStack {
            Group {
                if stations.isEmpty && isRefreshing {
                    ProgressView("Fetching stations…")
                } else if let error, stations.isEmpty {
                    ContentUnavailableView(error, systemImage: "antenna.radiowaves.left.and.right.slash")
                } else if stations.isEmpty {
                    ContentUnavailableView("No stations found", systemImage: "fuelpump.slash")
                } else {
                    List(stations) { station in
                        NavigationLink(destination: StationDetailView(station: station)) {
                            StationRow(station: station)
                        }
                    }
                    .refreshable { await loadLive() }
                }
            }
            .navigationTitle("Nearby")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if isRefreshing {
                        ProgressView()
                    } else {
                        Button { Task { await loadLive() } } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                }
            }
        }
        .task { await loadCached() }
        .onChange(of: location.location) { _, _ in
            guard stations.isEmpty else { return }
            Task { await loadCached() }
        }
        .onAppear {
            if location.authorizationStatus == .notDetermined {
                location.requestPermission()
            }
            location.startUpdating()
        }
    }

    // Instant, works offline — merges into shared store.
    private func loadCached() async {
        guard let coord = location.location?.coordinate else {
            if location.authorizationStatus == .denied {
                error = "Location access denied"
            } else {
                error = "Waiting for location…"
            }
            return
        }
        error = nil
        try? await store.loadNearby(coord, radiusKm: radiusKm, api: api, cacheOnly: true)
    }

    // Live — may call GasBuddy if cell is stale.
    private func loadLive() async {
        guard let coord = location.location?.coordinate else { return }
        error = nil
        isRefreshing = true
        do {
            try await store.loadNearby(coord, radiusKm: radiusKm, api: api)
        } catch {
            if stations.isEmpty { self.error = error.localizedDescription }
        }
        isRefreshing = false
    }
}
