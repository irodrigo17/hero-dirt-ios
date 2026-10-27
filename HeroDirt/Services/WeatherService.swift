import CoreLocation
import Foundation
import WeatherKit

/// Serializes weather work, reserves capacity for selected places, and shares
/// server cooldowns between the rain map and place details. Costs are
/// conservative location equivalents, rather than HTTP request counts.
actor WeatherRequestBudget {
    private struct Charge {
        let date: Date
        let cost: Int
        let overlay: Bool
    }
    private var charges: [Charge] = []
    private var running = false
    private(set) var waitingDetails = 0
    private var cooldownUntil = Date.distantPast
    private let minuteLimit: Int
    private let overlayLimit: Int
    private let window: TimeInterval

    init(minuteLimit: Int = 300, overlayLimit: Int = 180, window: TimeInterval = 60) {
        self.minuteLimit = minuteLimit
        self.overlayLimit = overlayLimit
        self.window = window
    }

    func pause(until date: Date) { cooldownUntil = max(cooldownUntil, date) }

    func run<T: Sendable>(cost: Int, overlay: Bool = false,
                         operation: @Sendable () async throws -> T) async throws -> T {
        if !overlay { waitingDetails += 1 }
        defer { if !overlay { waitingDetails -= 1 } }
        while true {
            try Task.checkCancellation()
            let now = Date()
            charges.removeAll { now.timeIntervalSince($0.date) >= window * 1440 }
            if cooldownUntil > now {
                throw WeatherService.WeatherError.rateLimited(until: cooldownUntil)
            }
            let recent = charges.filter { now.timeIntervalSince($0.date) < window }
            let hourly = charges.filter { now.timeIntervalSince($0.date) < window * 60 }
            for (entries, limit, duration) in [(charges, 8000, window * 1440), (hourly, 4000, window * 60)] {
                if entries.reduce(0, { $0 + $1.cost }) + cost > limit {
                    throw WeatherService.WeatherError.rateLimited(until: (entries.first?.date ?? now).addingTimeInterval(duration))
                }
            }
            let total = recent.reduce(0) { $0 + $1.cost }
            let mapTotal = recent.filter(\.overlay).reduce(0) { $0 + $1.cost }
            if total + cost > minuteLimit || (overlay && mapTotal + cost > overlayLimit) {
                let retry = (recent.first?.date ?? now).addingTimeInterval(window)
                throw WeatherService.WeatherError.rateLimited(until: retry)
            }
            if !running && (!overlay || waitingDetails == 0) { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        running = true
        charges.append(Charge(date: Date(), cost: cost, overlay: overlay))
        defer { running = false }
        return try await operation()
    }
}

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
    static let requestBudget = WeatherRequestBudget()
    private static let forecastBudget = WeatherRequestBudget()

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
        case rateLimited(until: Date)

        var errorDescription: String? {
            switch self {
            case .rateLimited:
                return String(localized: "Weather requests are paused. Please try again later.")
            case .invalidURL:
                return String(localized: "Could not build request URL.")
            case .httpError(let statusCode):
                switch statusCode {
                case 429: return String(localized: "Too many requests. Please try again in a minute.")
                case 500...599:
                    return String(localized: "Weather service is temporarily unavailable.")
                default: return String(localized: "Weather service error (HTTP \(statusCode)).")
                }
            case .invalidResponse:
                return String(localized: "Invalid response from weather service.")
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

    static func retryDate(response: HTTPURLResponse, data: Data, now: Date = Date()) -> Date {
        if let value = response.value(forHTTPHeaderField: "Retry-After") {
            if let seconds = TimeInterval(value), seconds.isFinite, seconds >= 0 {
                return now.addingTimeInterval(max(1, seconds))
            }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
            if let date = formatter.date(from: value), date > now { return date }
        }
        let reason = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["reason"] as? String ?? ""
        // Without a Retry-After header, use a conservative window based on
        // the provider's error reason; do not promise a one-minute reset.
        let delay: TimeInterval = reason.localizedCaseInsensitiveContains("daily") ? 86400
            : reason.localizedCaseInsensitiveContains("hourly") ? 3600 : 60
        return now.addingTimeInterval(delay)
    }

    private static func requestData(url: URL, session: URLSession) async throws -> Data {
        try Task.checkCancellation()
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw WeatherError.invalidResponse }
        if http.statusCode == 429 {
            let until = retryDate(response: http, data: data)
            await requestBudget.pause(until: until)
            throw WeatherError.rateLimited(until: until)
        }
        guard (200...299).contains(http.statusCode) else {
            throw WeatherError.httpError(statusCode: http.statusCode)
        }
        return data
    }

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

            let data = try await requestBudget.run(cost: chunk.count, overlay: true) {
                try await requestData(url: url, session: session)
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

        return try await requestBudget.run(cost: 3) {
            // A prior caller may have filled the cache while this one queued.
            if let cached = await cache.getRainfall(key) {
                return RainfallSummary(daily: cached)
            }
            let data = try await requestData(url: url, session: session ?? detailSession)
            let summary = try parseResponse(data)
            await cache.setRainfall(key, summary.dailyHistory + summary.upcoming)
            return summary
        }
    }

    // MARK: - WeatherKit Forecast

    static func fetchRainForecast(latitude: Double, longitude: Double)
        async throws -> RainForecast
    {
        let key = WeatherCache.key(latitude: latitude, longitude: longitude)
        if let cached = await cache.getForecast(key), cached.daily != nil { return cached }

        return try await forecastBudget.run(cost: 1) {
            if let cached = await cache.getForecast(key), cached.daily != nil { return cached }
            try Task.checkCancellation()
            let location = CLLocation(latitude: latitude, longitude: longitude)
            let daily = try await WeatherKit.WeatherService.shared.weather(
                for: location,
                including: .daily
            )

            let days = daily.forecast.map {
                DailyRainForecast(
                    date: $0.date,
                    amount: $0.precipitationAmountByType.rainfall.converted(to: .millimeters).value,
                    precipitationChance: $0.precipitationChance
                )
            }

            func sum(_ n: Int) -> Double { days.prefix(n).reduce(0) { $0 + $1.amount } }

            let result = RainForecast(
                next1Day: sum(1),
                next2Days: sum(2),
                next3Days: sum(3),
                next7Days: sum(7),
                daily: days
            )
            await cache.setForecast(key, result)
            return result
        }
    }
}
