import SwiftUI
import MapKit

struct MapStationsView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var store: StationStore
    @StateObject private var location = LocationManager.shared

    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var selectedStation: Station?
    @State private var isLoading = false
    @State private var error: String?
    @State private var lastAutoLoad: Date = .distantPast

    private var visibleStations: [Station] {
        guard let region = visibleRegion else { return [] }
        return store.stations(in: region)
    }

    var body: some View {
        NavigationStack {
            Map(position: $position, selection: $selectedStation) {
                ForEach(visibleStations) { station in
                    if let price = station.regularPrice?.formattedPrice {
                        Marker(price, systemImage: "fuelpump.fill", coordinate: CLLocationCoordinate2D(
                            latitude: station.lat,
                            longitude: station.lng
                        ))
                        .tint(station.isStale ? .orange : .green)
                        .tag(station)
                    } else {
                        Marker(station.name, systemImage: "fuelpump", coordinate: CLLocationCoordinate2D(
                            latitude: station.lat,
                            longitude: station.lng
                        ))
                        .tint(.gray)
                        .tag(station)
                    }
                }
                UserAnnotation()
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                visibleRegion = context.region
                Task { await autoLoad() }
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
            .navigationTitle("Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { Task { await loadVisible(live: true) } } label: {
                        if isLoading {
                            ProgressView()
                        } else {
                            Label("Refresh area", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(isLoading)
                }
            }
            .overlay(alignment: .bottom) {
                if let error {
                    Text(error)
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.regularMaterial)
                        .clipShape(Capsule())
                        .padding(.bottom, 8)
                }
            }
            .sheet(item: $selectedStation) { station in
                NavigationStack {
                    StationDetailView(station: station)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { selectedStation = nil }
                            }
                        }
                }
                .presentationDetents([.medium])
            }
        }
        .onAppear {
            location.startUpdating()
        }
    }

    private func autoLoad() async {
        guard Date().timeIntervalSince(lastAutoLoad) > 60 else { return }
        lastAutoLoad = Date()
        // Show cache instantly, then fetch live in background.
        await loadVisible(live: false)
        Task { await loadVisible(live: true) }
    }

    private func loadVisible(live: Bool) async {
        let region = visibleRegion ?? {
            guard let loc = location.location else { return nil }
            return MKCoordinateRegion(center: loc.coordinate, latitudinalMeters: 16_000, longitudinalMeters: 16_000)
        }()
        guard let region else { return }

        let latSpan = region.span.latitudeDelta
        let lngSpan = region.span.longitudeDelta
        guard latSpan * lngSpan <= 0.5 else {
            error = "Zoom in to load stations"
            return
        }
        error = nil

        if live {
            guard !isLoading else { return }
            isLoading = true
            do {
                try await store.loadNearby(region.center, radiusKm: max(latSpan, lngSpan) * 111 / 2, api: api)
            } catch {
                self.error = error.localizedDescription
            }
            isLoading = false
        } else {
            await store.loadBbox(region, api: api)
        }
    }
}

extension Station: Hashable {
    static func == (lhs: Station, rhs: Station) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
