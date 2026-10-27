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

        do {
            try Task.checkCancellation()
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse else { return nil }
            if http.statusCode == 429 {
                // Do not bypass the store's five-per-minute budget with an
                // automatic retry. Pause all queued soil work together.
                let until = WeatherService.retryDate(response: http, data: data)
                await store.pause(until: until)
                return nil
            }
            guard (200...299).contains(http.statusCode) else {
                logger.error("SoilGrids HTTP \(http.statusCode)")
                return nil
            }
            return try parseResponse(data)
        } catch {
            if !Task.isCancelled {
                logger.error("SoilGrids request failed: \(error.localizedDescription, privacy: .public)")
            }
            return nil
        }
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
    private struct Flight {
        let id: UUID
        let task: Task<SoilData?, Never>
        var waiters: Set<UUID>
    }
    private var inFlight: [Key: Flight] = [:]
    private var requestTimes: [Date] = []
    private var cooldownUntil = Date.distantPast

    func pause(until date: Date) { cooldownUntil = max(cooldownUntil, date) }

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
        let waiter = UUID()
        let flight: Flight
        if var existing = inFlight[key] {
            existing.waiters.insert(waiter)
            inFlight[key] = existing
            flight = existing
        } else {
            let task = Task<SoilData?, Never> {
                do { try await self.waitForSlot() } catch { return nil }
                guard !Task.isCancelled else { return nil }
                return await fetch()
            }
            flight = Flight(id: UUID(), task: task, waiters: [waiter])
            inFlight[key] = flight
        }
        let result = await withTaskCancellationHandler {
            await flight.task.value
        } onCancel: {
            Task { await self.cancelWaiter(waiter, key: key, flightID: flight.id) }
        }
        if inFlight[key]?.id == flight.id {
            inFlight[key] = nil
            if let result {
                entries[Self.storageKey(key)] = result
                persist()
            }
        }
        return Task.isCancelled ? nil : result
    }

    private func cancelWaiter(_ waiter: UUID, key: Key, flightID: UUID) {
        guard var flight = inFlight[key], flight.id == flightID else { return }
        flight.waiters.remove(waiter)
        if flight.waiters.isEmpty {
            inFlight[key] = nil
            flight.task.cancel()
        } else {
            inFlight[key] = flight
        }
    }

    private func waitForSlot() async throws {
        while true {
            try Task.checkCancellation()
            let now = Date()
            requestTimes.removeAll { now.timeIntervalSince($0) >= window }
            if requestTimes.count < maxRequests && now >= cooldownUntil {
                requestTimes.append(now)
                return
            }
            let quotaWait = requestTimes.count >= maxRequests
                ? window - now.timeIntervalSince(requestTimes[0]) + 0.1 : 0
            let wait = max(0.01, quotaWait, cooldownUntil.timeIntervalSince(now))
            try await Task.sleep(for: .seconds(wait))
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
