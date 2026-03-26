import Combine
import Foundation

struct EIAAverage: Codable {
    let state: String
    let regular: Double?
    let period: String
    let fetchedAt: Int64
}

@MainActor
final class EIAService: ObservableObject {
    static let shared = EIAService()

    // state abbreviation -> price per gallon
    private(set) var averages: [String: Double] = [:]

    private let cacheKey = "eia_averages_cache"
    private let cacheDateKey = "eia_averages_fetched_at"
    private let ttl: TimeInterval = 7 * 24 * 60 * 60

    func load(api: APIClient) async {
        // Use cached data if fresh
        if let cached = loadCache(), !cached.isEmpty {
            averages = cached
        }

        // Refresh in background if stale
        let fetchedAt = UserDefaults.standard.double(forKey: cacheDateKey)
        if Date().timeIntervalSince1970 - fetchedAt > ttl {
            await refresh(api: api)
        }
    }

    func deviation(for station: Station) -> Double? {
        guard let state = station.state,
              let avg = averages[state],
              let priceStr = station.regularPrice?.formattedPrice,
              let price = parsePrice(priceStr) else { return nil }
        return price - avg
    }

    private func refresh(api: APIClient) async {
        do {
            let data = try await api.fetchEIAAverages()
            var map: [String: Double] = [:]
            for entry in data {
                if let price = entry.regular {
                    map[entry.state] = price
                }
            }
            averages = map
            saveCache(map)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: cacheDateKey)
        } catch {
            print("EIA refresh failed: \(error)")
        }
    }

    private func parsePrice(_ s: String) -> Double? {
        Double(s.trimmingCharacters(in: .init(charactersIn: "$")))
    }

    private func saveCache(_ map: [String: Double]) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
    }

    private func loadCache() -> [String: Double]? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode([String: Double].self, from: data)
    }
}
