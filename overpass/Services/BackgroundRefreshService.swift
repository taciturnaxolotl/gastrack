import CoreLocation
import Foundation

/// Lightweight refresh logic — called when the app becomes active.
/// No background modes or BGTaskScheduler needed.
enum BackgroundRefreshService {
    private static let nearbyKey  = "last_nearby_refresh"
    private static let routeKey   = "last_route_refresh"
    private static let nearbyTTL: TimeInterval = 30 * 60    // 30 min
    private static let routeTTL:  TimeInterval = 6 * 60 * 60 // 6 h

    static func refreshIfNeeded() async {
        async let _ = refreshNearbyIfNeeded()
        async let _ = refreshRouteIfNeeded()
    }

    // MARK: - Nearby

    static func refreshNearbyIfNeeded() async {
        let last = UserDefaults.standard.double(forKey: nearbyKey)
        guard Date().timeIntervalSince1970 - last > nearbyTTL else { return }

        let lat = UserDefaults.standard.double(forKey: "last_lat")
        let lng = UserDefaults.standard.double(forKey: "last_lng")
        guard lat != 0 || lng != 0 else { return }

        if let results = try? await APIClient.shared.fetchNearby(lat: lat, lng: lng, radiusKm: 16) {
            let center = CLLocationCoordinate2D(latitude: lat, longitude: lng)
            await MainActor.run { StationStore.shared.replace(results, near: center, radiusKm: 16) }
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: nearbyKey)
        }
    }

    // MARK: - Route

    static func refreshRouteIfNeeded() async {
        let last = UserDefaults.standard.double(forKey: routeKey)
        guard Date().timeIntervalSince1970 - last > routeTTL else { return }

        guard let json = UserDefaults.standard.string(forKey: "route_points"),
              let data = json.data(using: .utf8),
              let points = try? JSONDecoder().decode([[Double]].self, from: data),
              !points.isEmpty else { return }

        if let response = try? await APIClient.shared.prefetchRoute(points: points) {
            await MainActor.run { StationStore.shared.merge(response.stations) }
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: routeKey)
        }
    }

    /// Call after a successful manual prefetch to reset the route TTL.
    static func markRouteRefreshed() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: routeKey)
    }
}
