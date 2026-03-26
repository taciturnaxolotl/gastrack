import SwiftUI
import MapKit

struct StationDetailView: View {
    let station: Station
    @EnvironmentObject private var eia: EIAService

    var body: some View {
        List {
            Section {
                Button {
                    openInMaps()
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        if let address = station.address {
                            Text(address)
                        }
                        if let city = station.city, let state = station.state {
                            Text("\(city), \(state) \(station.zip ?? "")".trimmingCharacters(in: .whitespaces))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.subheadline)
                }
                .foregroundStyle(.primary)
            } header: {
                Label("Location", systemImage: "mappin")
            }

            Section {
                ForEach(station.prices) { price in
                    HStack {
                        Text(price.nickname)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            if let fp = price.formattedPrice {
                                Text(fp)
                            } else {
                                Text("Not reported").foregroundStyle(.secondary)
                            }
                            if price.nickname == "Regular", let dev = eia.deviation(for: station) {
                                Text(deviationLabel(dev))
                                    .font(.caption2.bold())
                                    .foregroundStyle(dev < 0 ? .green : .red)
                            }
                        }
                    }
                }
            } header: {
                Text("Prices")
            } footer: {
                let date = Date(timeIntervalSince1970: Double(station.fetchedAt) / 1000)
                HStack(spacing: 6) {
                    Text("Fetched \(date.formatted(.relative(presentation: .named)))")
                    if station.isStale {
                        Label("May be outdated", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .navigationTitle(station.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func openInMaps() {
        let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: station.lat, longitude: station.lng))
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = station.name
        mapItem.openInMaps()
    }

    private func deviationLabel(_ dev: Double) -> String {
        let prefix = dev < 0 ? "-" : "+"
        return "\(prefix)$\(String(format: "%.2f", abs(dev))) vs state avg"
    }
}
