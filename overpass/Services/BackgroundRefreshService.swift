import CoreLocation
import Foundation
import MapKit

/// Lightweight refresh logic — called when the app becomes active.
/// No background modes or BGTaskScheduler needed.
enum BackgroundRefreshService {
    private static let nearbyKey: String = "last_nearby_refresh"
    private static let routeKey:  String = "last_route_refresh"
    private static let nearbyTTL: TimeInterval = 30 * 60     // 30 min
    private static let routeTTL:  TimeInterval = 6 * 60 * 60 // 6 h

    static func refreshIfNeeded() async {
        async let _ = refreshNearbyIfNeeded()
        async let _ = refreshRoutesIfNeeded()
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

    // MARK: - Routes

    static func refreshRoutesIfNeeded() async {
        let last = UserDefaults.standard.double(forKey: routeKey)
        guard Date().timeIntervalSince1970 - last > routeTTL else { return }

        let routes = await MainActor.run {
            RouteStore.shared.routes.filter { $0.lastCachedAt != nil }
        }
        guard !routes.isEmpty else { return }

        for saved in routes {
            let req = MKDirections.Request()
            let to = saved.toCoordinate
            req.destination = MKMapItem(location: CLLocation(latitude: to.latitude, longitude: to.longitude), address: nil)
            if let from = saved.fromCoordinate {
                req.source = MKMapItem(location: CLLocation(latitude: from.latitude, longitude: from.longitude), address: nil)
            } else {
                req.source = .forCurrentLocation()
            }
            req.transportType = .automobile

            guard let mkRoute = try? await MKDirections(request: req).calculate().routes.first else { continue }
            let points = extractPoints(from: mkRoute.polyline)
            if let response = try? await APIClient.shared.prefetchRoute(points: points) {
                await MainActor.run { StationStore.shared.merge(response.stations) }
            }
        }

        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: routeKey)
    }

    /// Call after a successful manual prefetch to reset the route TTL.
    static func markRouteRefreshed() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: routeKey)
    }

    // MARK: - Helpers

    private static func extractPoints(from polyline: MKPolyline, max: Int = 400) -> [[Double]] {
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
