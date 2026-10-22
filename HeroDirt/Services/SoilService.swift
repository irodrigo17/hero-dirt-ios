import Foundation
import os

// MARK: - SoilService

/// Soil texture from ISRIC SoilGrids. Soil doesn't change, so results are
/// cached on disk indefinitely and saved places keep their own copy
/// (`Place.soil`, synced through iCloud). SoilGrids is a slow beta API with a
/// fair-use limit of about 5 requests a minute, so requests are de-duplicated
/// and throttled. Failures are never cached: callers fall back to an
/// estimated loam and the next request tries again.
enum SoilService {

    static let store = SoilStore()

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()

    private static let logger = Logger(subsystem: "com.herodirt.app", category: "Soil")

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

    /// The soil to use for a location: the user's override, then the place's
    /// stored soil, then a (cached or fetched) SoilGrids lookup, then loam.
    static func resolve(
        override: SoilOverride?,
        stored: SoilData?,
        latitude: Double,
        longitude: Double
    ) async -> SoilData {
        if let override { return override.asSoilData }
        if let stored { return stored }
        return await fetchSoilData(latitude: latitude, longitude: longitude) ?? .loam
    }

    // MARK: - Fetch

    /// Cached or freshly fetched soil, or nil if SoilGrids couldn't answer.
    static func fetchSoilData(latitude: Double, longitude: Double) async -> SoilData? {
        await store.soil(latitude: latitude, longitude: longitude) {
            await request(latitude: latitude, longitude: longitude)
        }
    }

    private static func request(latitude: Double, longitude: Double) async -> SoilData? {
        guard var components = URLComponents(
            string: "https://rest.isric.org/soilgrids/v2.0/properties/query"
        ) else { return nil }

        components.queryItems = [
            URLQueryItem(name: "lon", value: String(format: "%.4f", longitude)),
            URLQueryItem(name: "lat", value: String(format: "%.4f", latitude)),
            URLQueryItem(name: "property", value: "sand"),
            URLQueryItem(name: "property", value: "clay"),
            URLQueryItem(name: "depth", value: "0-5cm"),
            URLQueryItem(name: "value", value: "mean"),
        ]
        guard let url = components.url else { return nil }

        for attempt in 0..<2 {
            do {
                let (data, response) = try await session.data(from: url)
                guard let http = response as? HTTPURLResponse else { return nil }
                if http.statusCode == 429, attempt == 0 {
                    logger.info("SoilGrids rate limited; retrying")
                    try await Task.sleep(for: .seconds(15))
                    continue
                }
                guard (200...299).contains(http.statusCode) else {
                    logger.error("SoilGrids HTTP \(http.statusCode)")
                    return nil
                }
                return try parseResponse(data)
            } catch {
                if !(error is CancellationError) {
                    logger.error("SoilGrids request failed: \(error.localizedDescription, privacy: .public)")
                }
                return nil
            }
        }
        return nil
    }

    // MARK: - Parsing (internal for testability)

    /// Parses a SoilGrids response. Returns `.loam` (estimated) when the
    /// location has no data (e.g. water or urban areas).
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

// MARK: - SoilStore

/// Disk-backed soil cache plus request de-duplication and throttling.
actor SoilStore {
    struct Key: Hashable, Codable {
        /// Hundredths of a degree (~1 km), floored so negatives bucket correctly.
        let lat: Int
        let lon: Int

        init(latitude: Double, longitude: Double) {
            lat = Int(floor(latitude * 100))
            lon = Int(floor(longitude * 100))
        }
    }

    private let fileURL: URL
    private var entries: [String: SoilData] = [:]
    private var loaded = false
    private var inFlight: [Key: Task<SoilData?, Never>] = [:]
    private var requestTimes: [Date] = []

    /// SoilGrids fair use: about 5 requests per minute.
    private let maxRequests: Int
    private let window: TimeInterval

    init(
        directory: URL = URL.applicationSupportDirectory,
        maxRequestsPerWindow: Int = 5,
        window: TimeInterval = 60
    ) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appending(path: "soil_cache.json")
        maxRequests = maxRequestsPerWindow
        self.window = window
    }

    private static func storageKey(_ key: Key) -> String { "\(key.lat)_\(key.lon)" }

    func cached(latitude: Double, longitude: Double) -> SoilData? {
        loadIfNeeded()
        return entries[Self.storageKey(Key(latitude: latitude, longitude: longitude))]
    }

    /// Returns cached soil, or runs `fetch` (throttled, one per location at a
    /// time) and caches a successful result.
    func soil(
        latitude: Double,
        longitude: Double,
        fetch: @escaping @Sendable () async -> SoilData?
    ) async -> SoilData? {
        loadIfNeeded()
        let key = Key(latitude: latitude, longitude: longitude)
        if let hit = entries[Self.storageKey(key)] { return hit }
        if let task = inFlight[key] { return await task.value }

        let task = Task<SoilData?, Never> {
            await self.waitForSlot()
            return await fetch()
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        if let result {
            entries[Self.storageKey(key)] = result
            persist()
        }
        return result
    }

    private func waitForSlot() async {
        while true {
            let now = Date()
            requestTimes.removeAll { now.timeIntervalSince($0) >= window }
            if requestTimes.count < maxRequests {
                requestTimes.append(now)
                return
            }
            let wait = window - now.timeIntervalSince(requestTimes[0]) + 0.1
            try? await Task.sleep(for: .seconds(wait))
        }
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: SoilData].self, from: data)
        {
            entries = decoded
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
