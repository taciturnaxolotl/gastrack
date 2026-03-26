import SwiftUI
import CoreLocation

struct StationRow: View {
    let station: Station
    @EnvironmentObject private var eia: EIAService
    @StateObject private var location = LocationManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(station.name)
                    .font(.headline)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    if let price = station.regularPrice?.formattedPrice {
                        Text(price)
                            .font(.headline)
                    } else {
                        Text("—")
                            .foregroundStyle(.secondary)
                    }
                    if let dev = eia.deviation(for: station) {
                        Text(deviationLabel(dev))
                            .font(.caption2.bold())
                            .foregroundStyle(dev < 0 ? .green : .red)
                    }
                }
            }

            HStack(spacing: 6) {
                if let city = station.city, let state = station.state {
                    Text("\(city), \(state)")
                }
                if let dist = distanceMiles {
                    Text("·")
                    Text(dist)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if station.isStale {
                Label("Stale data", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
    }

    private var distanceMiles: String? {
        guard let loc = location.location else { return nil }
        let stationLoc = CLLocation(latitude: station.lat, longitude: station.lng)
        let meters = loc.distance(from: stationLoc)
        let miles = meters / 1609.34
        return miles < 10 ? String(format: "%.1f mi", miles) : String(format: "%.0f mi", miles)
    }

    private func deviationLabel(_ dev: Double) -> String {
        let prefix = dev < 0 ? "-" : "+"
        return "\(prefix)$\(String(format: "%.2f", abs(dev))) vs state avg"
    }
}
