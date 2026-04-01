import Testing
import Foundation
@testable import RainClaude

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
}
