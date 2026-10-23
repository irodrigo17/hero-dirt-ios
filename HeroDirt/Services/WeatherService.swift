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
        rainfallURL = directory.appending(path: "hero_dirt_rainfall_v3.json")
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
        let utcOffsetSeconds: Int?
        let daily: DailyData
        let hourly: HourlyData?

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

        enum CodingKeys: String, CodingKey {
            case utcOffsetSeconds = "utc_offset_seconds"
            case daily
            case hourly
        }
    }

    struct HourlyData: Codable {
        let time: [String]
        let precipitation: [Double?]
        let et0FaoEvapotranspiration: [Double?]?

        enum CodingKeys: String, CodingKey {
            case time
            case precipitation
            case et0FaoEvapotranspiration = "et0_fao_evapotranspiration"
        }
    }

    /// Hourly-only response used by the rain map grid.
    struct HourlyResponse: Codable {
        let hourly: HourlyData
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
                case 429: return "Too many requests. Please try again in a minute."
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

    private static func localFormatter(_ format: String, offsetSeconds: Int) -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = format
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: offsetSeconds)
        return f
    }

    static func parseResponse(_ data: Data, now: Date = Date()) throws -> RainfallSummary {
        let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
        return RainfallSummary(daily: observedDaily(from: decoded, now: now))
    }

    /// Daily rain and ET0, with **today** limited to what has actually
    /// happened so far. Open-Meteo's daily values for today are full-day
    /// totals that include the forecast for the remaining hours; when hourly
    /// data is present, today's values are re-summed from hours up to `now`
    /// (in the location's time zone). Days after today are returned flagged
    /// `isForecast`.
    static func observedDaily(from response: OpenMeteoResponse, now: Date) -> [DailyWeatherData] {
        let offset = response.utcOffsetSeconds ?? TimeZone.current.secondsFromGMT(for: now)
        let today = localFormatter("yyyy-MM-dd", offsetSeconds: offset).string(from: now)
        let hourFormatter = localFormatter("yyyy-MM-dd'T'HH:mm", offsetSeconds: offset)

        // Observed (≤ now) hourly sums for today.
        var todayRain: Double?
        var todayET0: Double?
        if let hourly = response.hourly {
            var rain = 0.0
            var et0 = 0.0
            for (i, time) in hourly.time.enumerated() where time.hasPrefix(today) {
                guard let hourDate = hourFormatter.date(from: time), hourDate <= now else { continue }
                rain += i < hourly.precipitation.count ? (hourly.precipitation[i] ?? 0) : 0
                if let values = hourly.et0FaoEvapotranspiration, i < values.count {
                    et0 += values[i] ?? 0
                }
            }
            todayRain = rain
            todayET0 = et0
        }

        var daily: [DailyWeatherData] = []
        let days = response.daily
        for (i, dateString) in days.time.enumerated() {
            guard i < days.precipitationSum.count,
                  let date = Self.dateFormatter.date(from: dateString)
            else { continue }
            var amount = days.precipitationSum[i] ?? 0
            var et0 = days.et0FaoEvapotranspiration.flatMap { i < $0.count ? $0[i] : nil } ?? 0
            if dateString == today {
                amount = todayRain ?? amount
                et0 = todayET0 ?? et0
            }
            daily.append(DailyWeatherData(date: date, amount: amount, et0: et0, isForecast: dateString > today))
        }
        return daily
    }

    /// Groups an hourly series (oldest first) into rolling 24-hour buckets,
    /// most recent first: bucket 0 is the last 24 hours.
    static func rollingDays(from hourly: HourlyData, now: Date = Date()) -> [DailyWeatherData] {
        let values = hourly.precipitation.map { $0 ?? 0 }
        var result: [DailyWeatherData] = []
        var end = values.count
        var dayIndex = 0
        while end > 0 {
            let start = max(0, end - 24)
            let sum = values[start..<end].reduce(0, +)
            let date = Calendar.current.date(byAdding: .day, value: -dayIndex, to: now) ?? now
            result.append(DailyWeatherData(date: date, amount: sum))
            end = start
            dayIndex += 1
        }
        return result
    }

    // MARK: - Network

    private static let detailSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    /// Rain for many points at once (rain map grid). Each point gets rolling
    /// 24-hour totals for the last `pastDays` days, observed rain only.
    /// Throws on HTTP errors (e.g. 429) so the caller can tell the user.
    static func fetchRainfallBatch(
        points: [(lat: Double, lon: Double)],
        pastDays: Int,
        session: URLSession
    ) async throws -> [RainfallSummary?] {
        guard !points.isEmpty else { return [] }

        let chunkSize = 100
        var results = [RainfallSummary?](repeating: nil, count: points.count)

        for chunkStart in stride(from: 0, to: points.count, by: chunkSize) {
            try Task.checkCancellation()
            let chunk = Array(points[chunkStart..<min(chunkStart + chunkSize, points.count)])

            var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
            components.queryItems = [
                URLQueryItem(name: "latitude", value: chunk.map { String(format: "%.4f", $0.lat) }.joined(separator: ",")),
                URLQueryItem(name: "longitude", value: chunk.map { String(format: "%.4f", $0.lon) }.joined(separator: ",")),
                URLQueryItem(name: "hourly", value: "precipitation"),
                URLQueryItem(name: "past_hours", value: "\(pastDays * 24)"),
                URLQueryItem(name: "forecast_hours", value: "0"),
                URLQueryItem(name: "timezone", value: "GMT"),
            ]

            guard let url = components.url else { throw WeatherError.invalidURL }

            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse else { throw WeatherError.invalidResponse }
            guard (200...299).contains(http.statusCode) else {
                throw WeatherError.httpError(statusCode: http.statusCode)
            }

            let responses: [HourlyResponse]
            if let array = try? JSONDecoder().decode([HourlyResponse].self, from: data) {
                responses = array
            } else {
                responses = [try JSONDecoder().decode(HourlyResponse.self, from: data)]
            }

            for (i, resp) in responses.enumerated() {
                let globalIndex = chunkStart + i
                guard globalIndex < points.count else { break }
                results[globalIndex] = RainfallSummary(daily: rollingDays(from: resp.hourly))
            }
        }

        return results
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
            URLQueryItem(name: "latitude", value: String(format: "%.6f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.6f", longitude)),
            URLQueryItem(name: "daily", value: "precipitation_sum,et0_fao_evapotranspiration"),
            // Hourly values let us count only the part of today that has happened.
            URLQueryItem(name: "hourly", value: "precipitation,et0_fao_evapotranspiration"),
            URLQueryItem(name: "past_days", value: "30"),
            // Today plus 7 forecast days for the condition outlook.
            URLQueryItem(name: "forecast_days", value: "8"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]

        guard let url = components.url else {
            throw WeatherError.invalidURL
        }

        let (data, response) = try await (session ?? detailSession).data(from: url)

        guard let http = response as? HTTPURLResponse else {
            throw WeatherError.invalidResponse
        }

        guard (200...299).contains(http.statusCode) else {
            throw WeatherError.httpError(statusCode: http.statusCode)
        }

        let summary = try parseResponse(data)
        await cache.setRainfall(key, summary.dailyHistory + summary.upcoming)
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
