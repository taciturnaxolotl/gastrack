import CoreLocation
import Foundation

struct SavedRoute: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var fromName: String? = nil
    var fromLat: Double? = nil
    var fromLng: Double? = nil
    var toName: String
    var toLat: Double
    var toLng: Double
    var distanceKm: Double? = nil
    var durationSeconds: Double? = nil
    var bboxMinLat: Double? = nil
    var bboxMinLng: Double? = nil
    var bboxMaxLat: Double? = nil
    var bboxMaxLng: Double? = nil
    var lastCachedAt: Date? = nil
    var cachedCount: Int? = nil

    nonisolated var fromCoordinate: CLLocationCoordinate2D? {
        guard let lat = fromLat, let lng = fromLng else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    nonisolated var toCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: toLat, longitude: toLng)
    }
}
