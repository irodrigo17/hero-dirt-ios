import Foundation
import Testing

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
        #expect(summary.last2Days == 5.2)  // 5.2 + 0.0
        #expect(summary.last3Days == 6.5)  // 5.2 + 0.0 + 1.3
        #expect(summary.daysSinceLastRain == 0)  // rain on most recent day
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
        #expect(
            WeatherService.WeatherError.invalidURL.errorDescription
                == "Could not build request URL."
        )
    }

    @Test func invalidResponseErrorDescription() {
        #expect(
            WeatherService.WeatherError.invalidResponse.errorDescription
                == "Invalid response from weather service."
        )
    }

    @Test func httpErrorRateLimitDescription() {
        #expect(
            WeatherService.WeatherError.httpError(statusCode: 429)
                .errorDescription == "Too many requests. Please try again in a minute."
        )
    }

    @Test func httpErrorServerDescription() {
        #expect(
            WeatherService.WeatherError.httpError(statusCode: 500)
                .errorDescription
                == "Weather service is temporarily unavailable."
        )
        #expect(
            WeatherService.WeatherError.httpError(statusCode: 503)
                .errorDescription
                == "Weather service is temporarily unavailable."
        )
    }

    @Test func httpErrorGenericDescription() {
        #expect(
            WeatherService.WeatherError.httpError(statusCode: 404)
                .errorDescription == "Weather service error (HTTP 404)."
        )
    }
}

struct WeatherRequestBudgetTests {
    private actor Order {
        var entries: [Int] = []
        func add(_ entry: Int) { entries.append(entry) }
    }

    @Test func overlayBudgetReservesCapacityForDetails() async throws {
        let budget = WeatherRequestBudget(minuteLimit: 10, overlayLimit: 6)
        _ = try await budget.run(cost: 6, overlay: true) { 1 }
        do {
            _ = try await budget.run(cost: 1, overlay: true) { Issue.record("Overlay should be paused"); return 1 }
            Issue.record("Expected overlay budget error")
        } catch let error as WeatherService.WeatherError {
            guard case .rateLimited = error else { Issue.record("Wrong error"); return }
        }
        #expect(try await budget.run(cost: 3) { 42 } == 42)
    }

    @Test func serverCooldownBlocksBothRequestTypes() async throws {
        let budget = WeatherRequestBudget()
        await budget.pause(until: Date().addingTimeInterval(300))
        for overlay in [false, true] {
            do {
                _ = try await budget.run(cost: 1, overlay: overlay) { Issue.record("No network during cooldown"); return 1 }
                Issue.record("Expected cooldown")
            } catch let error as WeatherService.WeatherError {
                guard case .rateLimited = error else { Issue.record("Wrong error"); return }
            }
        }
    }

    @Test func minuteBudgetRecoversAfterWindowExpires() async throws {
        let budget = WeatherRequestBudget(minuteLimit: 1, overlayLimit: 1, window: 0.05)
        _ = try await budget.run(cost: 1) { 1 }
        try await Task.sleep(for: .milliseconds(60))
        #expect(try await budget.run(cost: 1) { 2 } == 2)
    }

    @Test func selectedPlaceRunsBeforeQueuedOverlayAndCancelledWorkNeverStarts() async throws {
        let budget = WeatherRequestBudget()
        let (started, start) = AsyncStream<Void>.makeStream()
        let (release, unblock) = AsyncStream<Void>.makeStream()
        let first = Task {
            try await budget.run(cost: 1, overlay: true) {
                start.yield()
                for await _ in release { break }
                return 1
            }
        }
        for await _ in started { break }
        let order = Order()
        let map = Task { try await budget.run(cost: 1, overlay: true) { await order.add(2); return 2 } }
        let detail = Task { try await budget.run(cost: 1) { await order.add(3); return 3 } }
        for _ in 0..<100 {
            if await budget.waitingDetails > 0 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await budget.waitingDetails == 1)
        let cancelled = Task {
            try await budget.run(cost: 1) { Issue.record("Cancelled request must not start"); return 4 }
        }
        cancelled.cancel()
        unblock.yield()
        _ = try await first.value
        #expect(try await detail.value == 3)
        #expect(try await map.value == 2)
        #expect(await order.entries == [3, 2])
        do { _ = try await cancelled.value; Issue.record("Expected cancellation") }
        catch is CancellationError { }
    }

    @Test func retryAfterSupportsSecondsDatesAndLongerQuotaWindows() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let url = URL(string: "https://example.com")!
        func response(_ header: String?) throws -> HTTPURLResponse {
            try #require(HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil,
                                        headerFields: header.map { ["Retry-After": $0] }))
        }
        #expect(WeatherService.retryDate(response: try response("120"), data: Data(), now: now) == now.addingTimeInterval(120))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
        let date = now.addingTimeInterval(600)
        #expect(WeatherService.retryDate(response: try response(formatter.string(from: date)), data: Data(), now: now) == date)
        let hourly = Data(#"{"reason":"Hourly API request limit exceeded"}"#.utf8)
        #expect(WeatherService.retryDate(response: try response(nil), data: hourly, now: now) == now.addingTimeInterval(3600))
    }
}
