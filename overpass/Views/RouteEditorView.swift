import Combine
import CoreLocation
import MapKit
import SwiftUI

// MARK: - Search completer

private final class SearchCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var results: [MKLocalSearchCompletion] = []
    private var _inner: MKLocalSearchCompleter?

    // Lazy — MKLocalSearchCompleter is only created when the user starts typing,
    // avoiding a main-thread stall on sheet presentation.
    private var inner: MKLocalSearchCompleter {
        if let c = _inner { return c }
        let c = MKLocalSearchCompleter()
        c.delegate = self
        c.resultTypes = [.address, .pointOfInterest]
        _inner = c
        return c
    }

    func query(_ text: String, near region: MKCoordinateRegion?) {
        if let r = region { inner.region = r }
        inner.queryFragment = text
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        results = Array(completer.results.prefix(6))
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        results = []
    }
}

// MARK: - View

struct RouteEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var store: StationStore
    @EnvironmentObject private var routeStore: RouteStore
    @StateObject private var location = LocationManager.shared
    @StateObject private var completer = SearchCompleter()

    let initialRoute: SavedRoute?

    init(route: SavedRoute?) {
        self.initialRoute = route
    }

    enum ActiveField { case from, to }

    @State private var routeId: UUID = UUID()
    @State private var name: String = ""
    @State private var fromText: String = ""
    @State private var toText: String = ""
    @State private var fromItem: MKMapItem?
    @State private var toItem: MKMapItem?
    @State private var route: MKRoute?
    @State private var routePosition: MapCameraPosition = .automatic
    @State private var isPrefetching = false
    @State private var prefetchResult: (stations: Int, samples: Int)?
    @State private var routeStations: [Station] = []
    @State private var errorMsg: String?
    @FocusState private var focused: ActiveField?

    // Cache state — updated by prefetch() and restored from initialRoute
    @State private var sessionCachedAt: Date?
    @State private var sessionCachedCount: Int?
    @State private var sessionBboxMinLat: Double?
    @State private var sessionBboxMinLng: Double?
    @State private var sessionBboxMaxLat: Double?
    @State private var sessionBboxMaxLng: Double?

    private var isEditing: Bool { initialRoute != nil }
    private var canSave: Bool { !name.isEmpty && toItem != nil }
    private var canPrefetch: Bool { toItem != nil && !isPrefetching }

    var body: some View {
        NavigationStack {
            List {
                nameSection
                locationsSection

                if focused != nil && !completer.results.isEmpty {
                    suggestionsSection
                }

                if let route {
                    routePreviewSection(route)
                }

                prefetchSection

                if let errorMsg {
                    Section {
                        Label(errorMsg, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                if let r = prefetchResult {
                    Section {
                        LabeledContent("Stations cached", value: "\(r.stations)")
                        LabeledContent("Grid cells fetched", value: "\(r.samples)")
                    }
                }

                if !routeStations.isEmpty {
                    Section {
                        ForEach(routeStations) { station in
                            NavigationLink {
                                StationDetailView(station: station)
                            } label: {
                                StationRow(station: station)
                            }
                        }
                    } header: {
                        Text("\(routeStations.count) Stations Along Route")
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Route" : "New Route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear {
                restore()
                if initialRoute == nil { Task { await prefillCurrentLocation() } }
            }
        }
    }

    // MARK: - Sections

    private var nameSection: some View {
        Section("Route Name") {
            TextField("e.g. Morning Commute", text: $name)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .onSubmit { focused = .from }
        }
    }

    private var locationsSection: some View {
        Section {
            locationRow(
                systemImage: "location.fill", tint: .blue,
                text: $fromText, placeholder: "Current location", field: .from
            )
            locationRow(
                systemImage: "mappin.circle.fill", tint: .red,
                text: $toText, placeholder: "Destination", field: .to
            )
        }
    }

    private var suggestionsSection: some View {
        Section {
            ForEach(completer.results, id: \.self) { c in
                Button { pick(c) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.title).foregroundStyle(.primary)
                        if !c.subtitle.isEmpty {
                            Text(c.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func routePreviewSection(_ route: MKRoute) -> some View {
        Section {
            Map(position: $routePosition) {
                MapPolyline(route.polyline)
                    .stroke(.blue, lineWidth: 3)
            }
            .frame(height: 180)
            .listRowInsets(.init())
            .clipShape(RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 24) {
                Label(String(format: "%.0f km", route.distance / 1000), systemImage: "arrow.left.and.right")
                Label(formatDuration(route.expectedTravelTime), systemImage: "clock")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private var prefetchSection: some View {
        Section {
            Button {
                Task { await prefetch() }
            } label: {
                Group {
                    if isPrefetching {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Caching stations…")
                        }
                    } else {
                        Text("Cache Stations Now")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canPrefetch)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
    }

    // MARK: - Row builder

    @ViewBuilder
    private func locationRow(
        systemImage: String,
        tint: Color,
        text: Binding<String>,
        placeholder: String,
        field: ActiveField
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 24)

            TextField(placeholder, text: text)
                .focused($focused, equals: field)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
                .submitLabel(field == .from ? .next : .search)
                .onChange(of: text.wrappedValue) { _, new in
                    if focused == field {
                        completer.query(new, near: location.location.map {
                            MKCoordinateRegion(center: $0.coordinate,
                                              latitudinalMeters: 500_000,
                                              longitudinalMeters: 500_000)
                        })
                    }
                    if new.isEmpty {
                        if field == .from { fromItem = nil }
                        if field == .to { toItem = nil; route = nil }
                    }
                }
                .onSubmit { if field == .from { focused = .to } }

            if !text.wrappedValue.isEmpty {
                Button {
                    text.wrappedValue = ""
                    if field == .from { fromItem = nil }
                    if field == .to { toItem = nil; route = nil }
                    completer.results = []
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Actions

    private func restore() {
        guard let r = initialRoute else { return }
        name = r.name
        fromText = r.fromName ?? ""
        toText = r.toName
        if let coord = r.fromCoordinate {
            fromItem = MKMapItem(location: CLLocation(latitude: coord.latitude, longitude: coord.longitude), address: nil)
        }
        let to = r.toCoordinate
        toItem = MKMapItem(location: CLLocation(latitude: to.latitude, longitude: to.longitude), address: nil)
        routeId = r.id
        sessionCachedAt = r.lastCachedAt
        sessionCachedCount = r.cachedCount
        sessionBboxMinLat = r.bboxMinLat
        sessionBboxMinLng = r.bboxMinLng
        sessionBboxMaxLat = r.bboxMaxLat
        sessionBboxMaxLng = r.bboxMaxLng
        Task {
            await fetchRoute()
            loadStationsFromStore(r)
        }
    }

    private func prefillCurrentLocation() async {
        guard let loc = location.location,
              let request = MKReverseGeocodingRequest(location: loc),
              let item = try? await request.mapItems.first else { return }
        fromItem = item
        fromText = item.name ?? ""
    }

    private func pick(_ completion: MKLocalSearchCompletion) {
        let field = focused
        focused = nil
        completer.results = []
        Task {
            let req = MKLocalSearch.Request(completion: completion)
            guard let item = try? await MKLocalSearch(request: req).start().mapItems.first else { return }
            if field == .from {
                fromText = completion.title
                fromItem = item
            } else {
                toText = completion.title
                toItem = item
                if name.isEmpty {
                    name = fromText.isEmpty ? completion.title : "\(fromText) → \(completion.title)"
                }
            }
            await fetchRoute()
        }
    }

    private func fetchRoute() async {
        guard let dest = toItem else { return }
        let req = MKDirections.Request()
        req.source = fromItem ?? .forCurrentLocation()
        req.destination = dest
        req.transportType = .automobile
        guard let r = try? await MKDirections(request: req).calculate().routes.first else { return }
        route = r
        let rect = r.polyline.boundingMapRect
        routePosition = .rect(rect.insetBy(dx: -rect.size.width * 0.15, dy: -rect.size.height * 0.15))
    }

    private func prefetch() async {
        guard let dest = toItem else { return }
        errorMsg = nil
        isPrefetching = true
        defer { isPrefetching = false }

        let currentRoute: MKRoute
        if let r = route {
            currentRoute = r
        } else {
            let req = MKDirections.Request()
            req.source = fromItem ?? .forCurrentLocation()
            req.destination = dest
            req.transportType = .automobile
            guard let r = try? await MKDirections(request: req).calculate().routes.first else {
                errorMsg = "Could not calculate route"
                return
            }
            currentRoute = r
            route = r
        }

        do {
            let points = extractPoints(from: currentRoute.polyline)
            let response = try await api.prefetchRoute(points: points)
            store.merge(response.stations)
            prefetchResult = (stations: response.count, samples: response.samples)

            // Update session cache state so buildRoute() picks it up
            sessionCachedAt = Date()
            sessionCachedCount = response.count
            sessionBboxMinLat = response.bbox.minLat
            sessionBboxMinLng = response.bbox.minLng
            sessionBboxMaxLat = response.bbox.maxLat
            sessionBboxMaxLng = response.bbox.maxLng
            routeStore.save(buildRoute())

            let stations = response.stations
            Task {
                routeStations = await Task.detached(priority: .userInitiated) {
                    Self.filterAndSort(stations, polyline: nil)
                }.value
            }

            BackgroundRefreshService.markRouteRefreshed()
        } catch {
            errorMsg = error.localizedDescription
        }
    }

    private func save() {
        routeStore.save(buildRoute())
        dismiss()
    }

    private func buildRoute() -> SavedRoute {
        var r = initialRoute ?? SavedRoute(
            id: routeId,
            name: name,
            toName: toText,
            toLat: toItem?.location.coordinate.latitude ?? 0,
            toLng: toItem?.location.coordinate.longitude ?? 0
        )
        r.name = name
        r.fromName = fromText.isEmpty ? nil : fromText
        r.fromLat = fromItem?.location.coordinate.latitude
        r.fromLng = fromItem?.location.coordinate.longitude
        r.toName = toText
        r.toLat = toItem?.location.coordinate.latitude ?? r.toLat
        r.toLng = toItem?.location.coordinate.longitude ?? r.toLng
        if let mkRoute = route {
            r.distanceKm = mkRoute.distance / 1000
            r.durationSeconds = mkRoute.expectedTravelTime
        }
        r.lastCachedAt = sessionCachedAt
        r.cachedCount = sessionCachedCount
        r.bboxMinLat = sessionBboxMinLat
        r.bboxMinLng = sessionBboxMinLng
        r.bboxMaxLat = sessionBboxMaxLat
        r.bboxMaxLng = sessionBboxMaxLng
        return r
    }

    private func loadStationsFromStore(_ r: SavedRoute) {
        guard let minLat = r.bboxMinLat, let minLng = r.bboxMinLng,
              let maxLat = r.bboxMaxLat, let maxLng = r.bboxMaxLng else { return }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                            longitude: (minLng + maxLng) / 2)
        let region = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: maxLat - minLat, longitudeDelta: maxLng - minLng)
        )
        let candidates = store.stations(in: region)
        let polyline = route?.polyline
        Task {
            let sorted = await Task.detached(priority: .userInitiated) {
                Self.filterAndSort(candidates, polyline: polyline)
            }.value
            routeStations = sorted
        }
    }

    private nonisolated static func filterAndSort(_ stations: [Station], polyline: MKPolyline?) -> [Station] {
        let filtered: [Station]
        if let polyline {
            let count = polyline.pointCount
            let step = Swift.max(1, count / 200)
            var coords = [CLLocationCoordinate2D](repeating: .init(), count: count)
            polyline.getCoordinates(&coords, range: NSRange(location: 0, length: count))
            filtered = stations.filter { station in
                let loc = CLLocation(latitude: station.lat, longitude: station.lng)
                var i = 0
                while i < count {
                    if CLLocation(latitude: coords[i].latitude, longitude: coords[i].longitude)
                        .distance(from: loc) <= 2000 { return true }
                    i += step
                }
                return false
            }
        } else {
            filtered = stations
        }
        return filtered.sorted {
            ($0.regularPrice?.numericPrice ?? .infinity) < ($1.regularPrice?.numericPrice ?? .infinity)
        }
    }

    // MARK: - Helpers

    private func extractPoints(from polyline: MKPolyline, max: Int = 400) -> [[Double]] {
        let count = polyline.pointCount
        let step = Swift.max(1, Int(ceil(Double(count) / Double(max))))
        var coords = [CLLocationCoordinate2D](repeating: .init(), count: count)
        polyline.getCoordinates(&coords, range: NSRange(location: 0, length: count))
        var result: [[Double]] = []
        var i = 0
        while i < count { result.append([coords[i].latitude, coords[i].longitude]); i += step }
        return result
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m) min"
    }
}
