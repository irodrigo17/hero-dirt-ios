import Foundation

// MARK: - SoilService

enum SoilService {

    // MARK: - Cache

    private actor Cache {
        struct Key: Hashable {
            let lat: Int   // degrees × 10 → ~11 km precision
            let lon: Int
        }

        private var entries: [Key: SoilData] = [:]

        func get(_ key: Key) -> SoilData? { entries[key] }
        func set(_ key: Key, _ value: SoilData) { entries[key] = value }
    }

    private static let cache = Cache()

    // MARK: - API Response

    struct SoilGridsResponse: Codable {
        let properties: Properties

        struct Properties: Codable {
            let layers: [Layer]
        }

        struct Layer: Codable {
            let name: String
            let depths: [Depth]
        }

        struct Depth: Codable {
            let values: Values
        }

        struct Values: Codable {
            let mean: Double?
        }
    }

    // MARK: - Resolve

    static func resolveOrFetch(
        override: SoilOverride?,
        latitude: Double,
        longitude: Double
    ) async -> SoilData {
        if let override { return override.asSoilData }
        return await fetchSoilData(latitude: latitude, longitude: longitude)
    }

    // MARK: - Fetch

    static func fetchSoilData(latitude: Double, longitude: Double) async -> SoilData {
        let key = Cache.Key(lat: Int(latitude * 10), lon: Int(longitude * 10))

        if let cached = await cache.get(key) { return cached }

        guard var components = URLComponents(
            string: "https://rest.isric.org/soilgrids/v2.0/properties/query"
        ) else { return .loam }

        components.queryItems = [
            URLQueryItem(name: "lon", value: String(format: "%.4f", longitude)),
            URLQueryItem(name: "lat", value: String(format: "%.4f", latitude)),
            URLQueryItem(name: "property", value: "sand"),
            URLQueryItem(name: "property", value: "clay"),
            URLQueryItem(name: "depth", value: "0-5cm"),
            URLQueryItem(name: "value", value: "mean"),
        ]

        guard let url = components.url else { return .loam }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        let session = URLSession(configuration: config)

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse,
                (200...299).contains(http.statusCode)
            else { return .loam }

            let result = try parseResponse(data)
            await cache.set(key, result)
            return result
        } catch {
            return .loam
        }
    }

    // MARK: - Parsing (internal for testability)

    static func parseResponse(_ data: Data) throws -> SoilData {
        let decoded = try JSONDecoder().decode(SoilGridsResponse.self, from: data)

        var sandGPerKg: Double? = nil
        var clayGPerKg: Double? = nil

        for layer in decoded.properties.layers {
            switch layer.name {
            case "sand": sandGPerKg = layer.depths.first?.values.mean
            case "clay": clayGPerKg = layer.depths.first?.values.mean
            default: break
            }
        }

        guard let s = sandGPerKg, let c = clayGPerKg else { return .loam }

        return SoilData(
            sandFraction: max(0, min(1, s / 1000.0)),
            clayFraction: max(0, min(1, c / 1000.0)),
            isEstimated: false
        )
    }
}
