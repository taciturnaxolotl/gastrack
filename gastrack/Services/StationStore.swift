import Combine
import CoreLocation
import MapKit

@MainActor
final class StationStore: ObservableObject {
    static let shared = StationStore()

    @Published private(set) var byId: [String: Station] = [:]

    func merge(_ stations: [Station]) {
        for s in stations { byId[s.id] = s }
    }

    // Filtered + sorted by distance from a coordinate.
    func stations(near coord: CLLocationCoordinate2D, radiusKm: Double) -> [Station] {
        let latDelta = radiusKm / 111.0
        let lngDelta = radiusKm / (111.0 * cos(coord.latitude * .pi / 180))
        let userLoc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        return byId.values
            .filter {
                abs($0.lat - coord.latitude) <= latDelta &&
                abs($0.lng - coord.longitude) <= lngDelta
            }
            .sorted {
                CLLocation(latitude: $0.lat, longitude: $0.lng).distance(from: userLoc) <
                CLLocation(latitude: $1.lat, longitude: $1.lng).distance(from: userLoc)
            }
    }

    // Filtered to a map region.
    func stations(in region: MKCoordinateRegion) -> [Station] {
        let minLat = region.center.latitude - region.span.latitudeDelta / 2
        let maxLat = region.center.latitude + region.span.latitudeDelta / 2
        let minLng = region.center.longitude - region.span.longitudeDelta / 2
        let maxLng = region.center.longitude + region.span.longitudeDelta / 2
        return byId.values.filter {
            $0.lat >= minLat && $0.lat <= maxLat &&
            $0.lng >= minLng && $0.lng <= maxLng
        }
    }

    // Cache-only fetch for a map region.
    func loadBbox(_ region: MKCoordinateRegion, api: APIClient) async {
        let minLat = region.center.latitude - region.span.latitudeDelta / 2
        let maxLat = region.center.latitude + region.span.latitudeDelta / 2
        let minLng = region.center.longitude - region.span.longitudeDelta / 2
        let maxLng = region.center.longitude + region.span.longitudeDelta / 2
        if let results = try? await api.fetchBbox(minLat: minLat, minLng: minLng, maxLat: maxLat, maxLng: maxLng) {
            merge(results)
        }
    }

    // Live fetch — may call GasBuddy if cell is stale.
    func loadNearby(_ coord: CLLocationCoordinate2D, radiusKm: Double, api: APIClient, cacheOnly: Bool = false) async throws {
        let results = try await api.fetchNearby(
            lat: coord.latitude,
            lng: coord.longitude,
            radiusKm: radiusKm,
            cacheOnly: cacheOnly
        )
        merge(results)
    }
}
