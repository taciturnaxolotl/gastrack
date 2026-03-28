import Combine
import Foundation
import SwiftUI

final class RouteStore: ObservableObject {
    static let shared = RouteStore()

    @Published var routes: [SavedRoute] = []

    private let key = "sh.dunkirk.overpass.routes"

    private init() { load() }

    func save(_ route: SavedRoute) {
        if let i = routes.firstIndex(where: { $0.id == route.id }) {
            routes[i] = route
        } else {
            routes.append(route)
        }
        persist()
    }

    func delete(at offsets: IndexSet) {
        routes.remove(atOffsets: offsets)
        persist()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([SavedRoute].self, from: data)
        else { return }
        routes = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(routes) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
