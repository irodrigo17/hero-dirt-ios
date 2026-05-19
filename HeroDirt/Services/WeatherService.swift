import CoreLocation
import Foundation
import WeatherKit

// MARK: - WeatherCache

actor WeatherCache {

    // MARK: - Entry

    struct Entry<T: Codable>: Codable {
        let value: T
        let timestamp: Date
    }

    // MARK: - Storage

    let rainfallURL: URL
    let forecastURL: URL

    init(directory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]) {
        rainfallURL = directory.appending(path: "hero_dirt_rainfall.json")
        forecastURL = directory.appending(path: "hero_dirt_forecast.json")
    }

    // MARK: - State

    var rainfall: [String: Entry<[DailyWeatherData]>] = [:]
    var forecast: [String: Entry<RainForecast>] = [:]
    private var isLoaded = false
    var persistTask: Task<Void, Never>?

    // MARK: - TTL

    static let rainfallTTL: TimeInterval = 3600
    static let forecastTTL: TimeInterval = 3600

    // MARK: - Key

    static func key(latitude: Double, longitude: Double) -> String {
        "\(Int(latitude * 100))_\(Int(longitude * 100))"
    }

    // MARK: - Disk load (lazy, once per instance)

    private func loadIfNeeded() {
        guard !isLoaded else { return }
        isLoaded = true
        let now = Date()
        if let data = try? Data(contentsOf: rainfallURL),
            let entries = try? JSONDecoder().decode(
                [String: Entry<[DailyWeatherData]>].self, from: data)
        {
            rainfall = entries.filter {
                now.timeIntervalSince($0.value.timestamp) < Self.rainfallTTL
            }
        }
        if let data = try? Data(contentsOf: forecastURL),
            let entries = try? JSONDecoder().decode(
                [String: Entry<RainForecast>].self, from: data)
        {
            forecast = entries.filter {
                now.timeIntervalSince($0.value.timestamp) < Self.forecastTTL
            }
        }
    }

    // MARK: - Rainfall

    func getRainfall(_ key: String) -> [DailyWeatherData]? {
        loadIfNeeded()
        guard let entry = rainfall[key],
            Date().timeIntervalSince(entry.timestamp) < Self.rainfallTTL
        else { return nil }
        return entry.value
    }

    func setRainfall(_ key: String, _ daily: [DailyWeatherData]) {
        loadIfNeeded()
        rainfall[key] = Entry(value: daily, timestamp: Date())
        schedulePersist()
    }

    // MARK: - Forecast

    func getForecast(_ key: String) -> RainForecast? {
        loadIfNeeded()
        guard let entry = forecast[key],
            Date().timeIntervalSince(entry.timestamp) < Self.forecastTTL
        else { return nil }
        return entry.value
    }

    func setForecast(_ key: String, _ value: RainForecast) {
        loadIfNeeded()
        forecast[key] = Entry(value: value, timestamp: Date())
        schedulePersist()
    }

    // MARK: - Persist (debounced, background)

    private func schedulePersist() {
        persistTask?.cancel()
        let r = rainfall
        let f = forecast
        let rURL = rainfallURL
        let fURL = forecastURL
        persistTask = Task.detached(priority: .background) {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            if let data = try? JSONEncoder().encode(r) {
                try? data.write(to: rURL, options: .atomic)
            }
            if let data = try? JSONEncoder().encode(f) {
                try? data.write(to: fURL, options: .atomic)
            }
        }
    }

    // MARK: - Invalidation

    func invalidate(key: String) {
        rainfall.removeValue(forKey: key)
        forecast.removeValue(forKey: key)
    }

}

// MARK: - WeatherService

enum WeatherService {

    static let cache = WeatherCache()

    // MARK: - API Response

    struct OpenMeteoResponse: Codable {
        let daily: DailyData

        struct DailyData: Codable {
            let time: [String]
            let precipitationSum: [Double?]
            let et0FaoEvapotranspiration: [Double?]?

            enum CodingKeys: String, CodingKey {
                case time
                case precipitationSum = "precipitation_sum"
                case et0FaoEvapotranspiration = "et0_fao_evapotranspiration"
            }
        }
    }

    // MARK: - Errors

    enum WeatherError: LocalizedError {
        case invalidURL
        case httpError(statusCode: Int)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Could not build request URL."
            case .httpError(let statusCode):
                switch statusCode {
                case 429: return "Rate limited. Please try again later."
                case 500...599:
                    return "Weather service is temporarily unavailable."
                default: return "Weather service error (HTTP \(statusCode))."
                }
            case .invalidResponse:
                return "Invalid response from weather service."
            }
        }
    }

    // MARK: - Parsing

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func parseResponse(_ data: Data) throws -> RainfallSummary {
        let decoded = try JSONDecoder().decode(
            OpenMeteoResponse.self,
            from: data
        )

        var daily: [DailyWeatherData] = []
        for (i, dateString) in decoded.daily.time.enumerated() {
            guard i < decoded.daily.precipitationSum.count else { continue }
            guard let date = Self.dateFormatter.date(from: dateString) else { continue }
            let amount = decoded.daily.precipitationSum[i] ?? 0.0
            let et0 = decoded.daily.et0FaoEvapotranspiration.flatMap { arr in
                i < arr.count ? arr[i] : nil
            } ?? 0.0
            daily.append(DailyWeatherData(date: date, amount: amount, et0: et0))
        }

        return RainfallSummary(daily: daily)
    }

    // MARK: - Network

    private static let detailSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    static func fetchRainfallBatch(
        points: [(lat: Double, lon: Double)],
        pastDays: Int,
        session: URLSession
    ) async throws -> [RainfallSummary?] {
        guard !points.isEmpty else { return [] }

        let chunkSize = 100
        var results = [RainfallSummary?](repeating: nil, count: points.count)

        for chunkStart in stride(from: 0, to: points.count, by: chunkSize) {
            let chunk = Array(points[chunkStart..<min(chunkStart + chunkSize, points.count)])

            var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
            components.queryItems = [
                URLQueryItem(name: "latitude", value: chunk.map { String(format: "%.6f", $0.lat) }.joined(separator: ",")),
                URLQueryItem(name: "longitude", value: chunk.map { String(format: "%.6f", $0.lon) }.joined(separator: ",")),
                URLQueryItem(name: "daily", value: "precipitation_sum"),
                URLQueryItem(name: "past_days", value: "\(pastDays)"),
                URLQueryItem(name: "forecast_days", value: "1"),
                URLQueryItem(name: "timezone", value: "auto"),
            ]

            guard let url = components.url else { continue }

            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode)
            else { continue }

            let responses: [OpenMeteoResponse]
            if let array = try? JSONDecoder().decode([OpenMeteoResponse].self, from: data) {
                responses = array
            } else if let single = try? JSONDecoder().decode(OpenMeteoResponse.self, from: data) {
                responses = [single]
            } else {
                continue
            }

            for (i, resp) in responses.enumerated() {
                let globalIndex = chunkStart + i
                guard globalIndex < points.count else { break }
                results[globalIndex] = try? parseResponse(data: resp)
            }
        }

        return results
    }

    private static func parseResponse(data resp: OpenMeteoResponse) throws -> RainfallSummary {
        var daily: [DailyWeatherData] = []
        for (i, dateString) in resp.daily.time.enumerated() {
            guard i < resp.daily.precipitationSum.count else { continue }
            guard let date = Self.dateFormatter.date(from: dateString) else { continue }
            let amount = resp.daily.precipitationSum[i] ?? 0.0
            daily.append(DailyWeatherData(date: date, amount: amount))
        }
        return RainfallSummary(daily: daily)
    }

    static func fetchRainfall(
        latitude: Double,
        longitude: Double,
        session: URLSession? = nil
    ) async throws -> RainfallSummary {
        let key = WeatherCache.key(latitude: latitude, longitude: longitude)
        if let cached = await cache.getRainfall(key) {
            return RainfallSummary(daily: cached)
        }

        var components = URLComponents(
            string: "https://api.open-meteo.com/v1/forecast"
        )!
        components.queryItems = [
            URLQueryItem(
                name: "latitude",
                value: String(format: "%.6f", latitude)
            ),
            URLQueryItem(
                name: "longitude",
                value: String(format: "%.6f", longitude)
            ),
            URLQueryItem(name: "daily", value: "precipitation_sum,et0_fao_evapotranspiration"),
            URLQueryItem(name: "past_days", value: "30"),
            URLQueryItem(name: "forecast_days", value: "1"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]

        guard let url = components.url else {
            throw WeatherError.invalidURL
        }

        let (data, response) = try await (session ?? detailSession).data(
            from: url
        )

        guard let http = response as? HTTPURLResponse else {
            throw WeatherError.invalidResponse
        }

        guard (200...299).contains(http.statusCode) else {
            throw WeatherError.httpError(statusCode: http.statusCode)
        }

        let summary = try parseResponse(data)
        await cache.setRainfall(key, summary.dailyHistory)
        return summary
    }

    // MARK: - WeatherKit Forecast

    static func fetchRainForecast(latitude: Double, longitude: Double)
        async throws -> RainForecast
    {
        let key = WeatherCache.key(latitude: latitude, longitude: longitude)
        if let cached = await cache.getForecast(key) { return cached }

        let location = CLLocation(latitude: latitude, longitude: longitude)
        let daily = try await WeatherKit.WeatherService.shared.weather(
            for: location,
            including: .daily
        )

        let amounts = daily.forecast.prefix(7).map {
            $0.precipitationAmountByType.rainfall.converted(to: .millimeters)
                .value
        }

        func sum(_ n: Int) -> Double { amounts.prefix(n).reduce(0, +) }

        let result = RainForecast(
            next1Day: sum(1),
            next2Days: sum(2),
            next3Days: sum(3),
            next7Days: sum(7)
        )
        await cache.setForecast(key, result)
        return result
    }
}
