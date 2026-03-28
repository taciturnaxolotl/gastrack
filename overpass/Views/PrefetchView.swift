import CoreLocation
import MapKit
import SwiftUI

struct PrefetchView: View {
    @EnvironmentObject private var routeStore: RouteStore
    @StateObject private var location = LocationManager.shared
    @State private var editingRoute: SavedRoute?
    @State private var isAdding = false
    @State private var currentLocationName: String?

    var body: some View {
        NavigationStack {
            Group {
                if routeStore.routes.isEmpty {
                    ContentUnavailableView(
                        "No Routes",
                        systemImage: "road.lanes",
                        description: Text("Save a route to pre-cache gas stations along your drive.")
                    )
                } else {
                    List {
                        ForEach(routeStore.routes) { route in
                            Button {
                                editingRoute = route
                            } label: {
                                RouteRowView(route: route, currentLocationName: currentLocationName)
                            }
                            .tint(.primary)
                        }
                        .onDelete { routeStore.delete(at: $0) }
                    }
                }
            }
            .navigationTitle("Routes")
            .task(id: location.location) {
                guard let loc = location.location,
                      let request = MKReverseGeocodingRequest(location: loc),
                      let item = try? await request.mapItems.first else { return }
                currentLocationName = item.name
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { isAdding = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $isAdding) {
                RouteEditorView(route: nil)
            }
            .sheet(item: $editingRoute) { route in
                RouteEditorView(route: route)
            }
        }
    }
}

// MARK: - Row

private struct RouteRowView: View {
    let route: SavedRoute
    let currentLocationName: String?

    private var fromLabel: String? { route.fromName ?? currentLocationName }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(route.name)
                .font(.headline)
                .foregroundStyle(.primary)

            HStack(spacing: 4) {
                if let from = fromLabel {
                    Text(from)
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Text(route.toName)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if route.distanceKm != nil || route.durationSeconds != nil || route.cachedCount != nil {
                HStack(spacing: 10) {
                    if let km = route.distanceKm {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.left.and.right").imageScale(.small)
                            Text(String(format: "%.0f km", km))
                        }
                    }
                    if let secs = route.durationSeconds {
                        HStack(spacing: 3) {
                            Image(systemName: "clock").imageScale(.small)
                            Text(formatDuration(secs))
                        }
                    }
                    if let count = route.cachedCount {
                        HStack(spacing: 3) {
                            Image(systemName: "fuelpump").imageScale(.small)
                            Text("\(count) stations")
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

}
        .padding(.vertical, 2)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m) min"
    }
}
