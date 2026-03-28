import AppIntents
import CoreLocation
import MapKit

// MARK: - Entity

struct SavedRouteEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Route"
    static var defaultQuery = SavedRouteQuery()

    var id: UUID
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

// MARK: - Query

struct SavedRouteQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [SavedRouteEntity] {
        await MainActor.run {
            RouteStore.shared.routes
                .filter { identifiers.contains($0.id) }
                .map { SavedRouteEntity(id: $0.id, name: $0.name) }
        }
    }

    func suggestedEntities() async throws -> [SavedRouteEntity] {
        await MainActor.run {
            RouteStore.shared.routes.map { SavedRouteEntity(id: $0.id, name: $0.name) }
        }
    }
}

// MARK: - Intent

struct PrefetchRouteIntent: AppIntent {
    static var title: LocalizedStringResource = "Cache Route"
    static var description = IntentDescription("Cache gas station data along a saved route.")

    @Parameter(title: "Route") var route: SavedRouteEntity

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let saved = await MainActor.run(body: { RouteStore.shared.routes.first(where: { $0.id == route.id }) }) else {
            throw $route.needsValueError("Which route would you like to cache?")
        }

        let to = saved.toCoordinate
        let req = MKDirections.Request()
        req.destination = MKMapItem(location: CLLocation(latitude: to.latitude, longitude: to.longitude), address: nil)
        if let from = saved.fromCoordinate {
            req.source = MKMapItem(location: CLLocation(latitude: from.latitude, longitude: from.longitude), address: nil)
        } else {
            req.source = .forCurrentLocation()
        }
        req.transportType = .automobile

        guard let mkRoute = try? await MKDirections(request: req).calculate().routes.first else {
            return .result(dialog: "Couldn't calculate the route for \(saved.name).")
        }

        let points = extractPoints(from: mkRoute.polyline)
        let response = try await APIClient.shared.prefetchRoute(points: points)
        await MainActor.run {
            StationStore.shared.merge(response.stations)
            var updated = saved
            updated.lastCachedAt = Date()
            updated.cachedCount = response.count
            RouteStore.shared.save(updated)
        }
        await MainActor.run { BackgroundRefreshService.markRouteRefreshed() }

        return .result(dialog: "Cached \(response.count) stations along \(saved.name).")
    }

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
}

// MARK: - Shortcuts

struct OverpassShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PrefetchRouteIntent(),
            phrases: [
                "Cache \(\.$route) in \(.applicationName)",
                "Prefetch \(\.$route) in \(.applicationName)",
                "Update \(\.$route) stations in \(.applicationName)",
            ],
            shortTitle: "Cache Route",
            systemImageName: "arrow.down.circle.fill"
        )
    }
}
