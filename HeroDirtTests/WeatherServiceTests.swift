import Testing
import Foundation
@testable import HeroDirt

struct WeatherServiceTests {

    // MARK: - Valid response

    @Test func parseValidResponse() throws {
        let json = """
        {
            "daily": {
                "time": ["2025-03-01", "2025-02-28", "2025-02-27"],
                "precipitation_sum": [5.2, 0.0, 1.3]
            }
        }
        """
        let data = Data(json.utf8)
        let summary = try WeatherService.parseResponse(data)

        #expect(summary.last1Day == 5.2)
        #expect(summary.last2Days == 5.2)      // 5.2 + 0.0
        #expect(summary.last3Days == 6.5)       // 5.2 + 0.0 + 1.3
        #expect(summary.daysSinceLastRain == 0) // rain on most recent day
    }

    // MARK: - Nil precipitation values

    @Test func parseNilPrecipitationTreatedAsZero() throws {
        let json = """
        {
            "daily": {
                "time": ["2025-03-01", "2025-02-28"],
                "precipitation_sum": [null, 2.0]
            }
        }
        """
        let data = Data(json.utf8)
        let summary = try WeatherService.parseResponse(data)

        #expect(summary.last1Day == 0.0)
        #expect(summary.last2Days == 2.0)
    }

    // MARK: - Invalid JSON

    @Test func parseInvalidJSONThrows() {
        let data = Data("not json".utf8)
        #expect(throws: (any Error).self) {
            try WeatherService.parseResponse(data)
        }
    }

    @Test func parseEmptyJSONThrows() {
        let data = Data("{}".utf8)
        #expect(throws: (any Error).self) {
            try WeatherService.parseResponse(data)
        }
    }

    // MARK: - Edge cases

    @Test func parseEmptyTimeArray() throws {
        let json = """
        {
            "daily": {
                "time": [],
                "precipitation_sum": []
            }
        }
        """
        let data = Data(json.utf8)
        let summary = try WeatherService.parseResponse(data)

        #expect(summary.last1Day == 0)
        #expect(summary.last7Days == 0)
        #expect(summary.daysSinceLastRain == nil)
    }

    @Test func parseMismatchedArrayLengths() throws {
        let json = """
        {
            "daily": {
                "time": ["2025-03-01", "2025-02-28"],
                "precipitation_sum": [5.2]
            }
        }
        """
        let data = Data(json.utf8)
        let summary = try WeatherService.parseResponse(data)

        // Only one valid entry (the second has no matching precipitation)
        #expect(summary.last1Day == 5.2)
    }

    @Test func parseInvalidDateFormat() throws {
        let json = """
        {
            "daily": {
                "time": ["invalid-date"],
                "precipitation_sum": [5.2]
            }
        }
        """
        let data = Data(json.utf8)
        let summary = try WeatherService.parseResponse(data)

        // Invalid date is skipped
        #expect(summary.last1Day == 0)
    }

    // MARK: - WeatherError descriptions

    @Test func invalidURLErrorDescription() {
        #expect(WeatherService.WeatherError.invalidURL.errorDescription == "Could not build request URL.")
    }

    @Test func invalidResponseErrorDescription() {
        #expect(WeatherService.WeatherError.invalidResponse.errorDescription == "Invalid response from weather service.")
    }

    @Test func httpErrorRateLimitDescription() {
        #expect(WeatherService.WeatherError.httpError(statusCode: 429).errorDescription == "Rate limited. Please try again later.")
    }

    @Test func httpErrorServerDescription() {
        #expect(WeatherService.WeatherError.httpError(statusCode: 500).errorDescription == "Weather service is temporarily unavailable.")
        #expect(WeatherService.WeatherError.httpError(statusCode: 503).errorDescription == "Weather service is temporarily unavailable.")
    }

    @Test func httpErrorGenericDescription() {
        #expect(WeatherService.WeatherError.httpError(statusCode: 404).errorDescription == "Weather service error (HTTP 404).")
    }
}
