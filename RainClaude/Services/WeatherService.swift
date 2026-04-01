import Foundation

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
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Could not build request URL."
            case .invalidResponse: return "Invalid response from weather service."
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
            guard let date = formatter.date(from: dateString) else { continue }
            let amount = decoded.daily.precipitationSum[i] ?? 0.0
            daily.append(DailyRainfall(date: date, amount: amount))
        }

        return RainfallSummary(daily: daily)
    }

    // MARK: - Fetch

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

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw WeatherError.invalidResponse
        }

        return try parseResponse(data)
    }
}
