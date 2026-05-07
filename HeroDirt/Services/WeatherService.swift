import Foundation
import WeatherKit
import CoreLocation

enum WeatherService {

    // MARK: - API Response

    struct OpenMeteoResponse: Codable {
        let daily: DailyData

        struct DailyData: Codable {
            let time: [String]
            let precipitationSum: [Double?]

            enum CodingKeys: String, CodingKey {
                case time
                case precipitationSum = "precipitation_sum"
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
                case 500...599: return "Weather service is temporarily unavailable."
                default: return "Weather service error (HTTP \(statusCode))."
                }
            case .invalidResponse:
                return "Invalid response from weather service."
            }
        }
    }

    // MARK: - Parsing

    static func parseResponse(_ data: Data) throws -> RainfallSummary {
        let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        var daily: [DailyRainfall] = []
        for (i, dateString) in decoded.daily.time.enumerated() {
            guard i < decoded.daily.precipitationSum.count else { continue }
            guard let date = formatter.date(from: dateString) else { continue }
            let amount = decoded.daily.precipitationSum[i] ?? 0.0
            daily.append(DailyRainfall(date: date, amount: amount))
        }

        return RainfallSummary(daily: daily)
    }

    // MARK: - Network

    private static let detailSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    static func fetchRainfall(
        latitude: Double,
        longitude: Double,
        session: URLSession? = nil
    ) async throws -> RainfallSummary {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.6f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.6f", longitude)),
            URLQueryItem(name: "daily", value: "precipitation_sum"),
            URLQueryItem(name: "past_days", value: "30"),
            URLQueryItem(name: "forecast_days", value: "1"),
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

        return try parseResponse(data)
    }

    // MARK: - WeatherKit Forecast

    static func fetchRainForecast(latitude: Double, longitude: Double) async throws -> RainForecast {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        let daily = try await WeatherKit.WeatherService.shared.weather(for: location, including: .daily)

        let amounts = daily.forecast.prefix(7).map {
            $0.precipitationAmountByType.rainfall.converted(to: .millimeters).value
        }

        func sum(_ n: Int) -> Double { amounts.prefix(n).reduce(0, +) }

        return RainForecast(
            next1Day: sum(1),
            next2Days: sum(2),
            next3Days: sum(3),
            next7Days: sum(7)
        )
    }
}
