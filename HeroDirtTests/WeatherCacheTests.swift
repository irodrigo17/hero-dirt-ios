import Foundation
import Testing

@testable import HeroDirt

struct WeatherCacheTests {

    // Each test gets a fresh cache instance with disk files cleared.
    private func makeCache() async -> WeatherCache {
        let c = WeatherCache()
        await c._resetForTesting()
        return c
    }

    // MARK: - Rainfall cache

    @Test func rainfallCacheMissReturnsNil() async {
        let cache = await makeCache()
        #expect(await cache.getRainfall("0_0") == nil)
    }

    @Test func rainfallCacheHitReturnsValue() async {
        let cache = await makeCache()
        let daily = [DailyWeatherData(date: Date(), amount: 12.5, et0: 3.0)]
        await cache.setRainfall("10_20", daily)
        let result = await cache.getRainfall("10_20")
        #expect(result?.count == 1)
        #expect(result?.first?.amount == 12.5)
        #expect(result?.first?.et0 == 3.0)
    }

    @Test func rainfallDifferentKeysMiss() async {
        let cache = await makeCache()
        let daily = [DailyWeatherData(date: Date(), amount: 5.0, et0: 1.0)]
        await cache.setRainfall("10_20", daily)
        #expect(await cache.getRainfall("10_21") == nil)
    }

    @Test func rainfallExpiredEntryReturnsNil() async {
        let cache = await makeCache()
        // Manually inject an expired entry (timestamp 2 hours ago)
        let old = WeatherCache.Entry(
            value: [DailyWeatherData(date: Date(), amount: 5.0, et0: 1.0)],
            timestamp: Date(timeIntervalSinceNow: -WeatherCache.rainfallTTL - 1)
        )
        await MainActor.run { }  // yield so the actor processes
        // Write directly into the actor's dict
        let key = "10_20"
        // Set a value then overwrite timestamp via re-encoding trick is complex;
        // instead test via disk: write an expired entry to disk, load a new instance.
        let expired: [String: WeatherCache.Entry<[DailyWeatherData]>] = [key: old]
        if let data = try? JSONEncoder().encode(expired) {
            try? data.write(to: WeatherCache.rainfallURL, options: .atomic)
        }
        // New cache instance should prune the expired entry on load
        let cache2 = WeatherCache()  // don't reset — we want it to load from disk
        #expect(await cache2.getRainfall(key) == nil)
    }

    // MARK: - Forecast cache

    @Test func forecastCacheMissReturnsNil() async {
        let cache = await makeCache()
        #expect(await cache.getForecast("0_0") == nil)
    }

    @Test func forecastCacheHitReturnsValue() async {
        let cache = await makeCache()
        let fc = RainForecast(next1Day: 2.5, next2Days: 5.0, next3Days: 7.5, next7Days: 20.0)
        await cache.setForecast("10_20", fc)
        let result = await cache.getForecast("10_20")
        #expect(result?.next1Day == 2.5)
        #expect(result?.next7Days == 20.0)
    }

    // MARK: - Codable round-trips

    @Test func dailyWeatherDataRoundTrip() throws {
        let original = DailyWeatherData(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            amount: 12.3,
            et0: 4.5
        )
        let data = try JSONEncoder().encode([original])
        let decoded = try JSONDecoder().decode([DailyWeatherData].self, from: data)
        #expect(decoded.count == 1)
        #expect(decoded[0].amount == original.amount)
        #expect(decoded[0].et0 == original.et0)
        #expect(
            abs(
                decoded[0].date.timeIntervalSince1970
                    - original.date.timeIntervalSince1970
            ) < 1.0
        )
    }

    @Test func rainForecastRoundTrip() throws {
        let original = RainForecast(
            next1Day: 1.1, next2Days: 2.2, next3Days: 3.3, next7Days: 7.7
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RainForecast.self, from: data)
        #expect(decoded.next1Day == original.next1Day)
        #expect(decoded.next2Days == original.next2Days)
        #expect(decoded.next3Days == original.next3Days)
        #expect(decoded.next7Days == original.next7Days)
    }

    // MARK: - Disk persistence

    @Test func rainfallPersistedToDiskAndLoadedByNewInstance() async throws {
        let cache = await makeCache()
        let daily = [DailyWeatherData(date: Date(), amount: 8.0, et0: 2.5)]
        await cache.setRainfall("42_17", daily)

        // Wait for the debounced write (1 second + margin)
        try await Task.sleep(for: .milliseconds(1200))

        // New instance should load from disk
        let cache2 = WeatherCache()
        let result = await cache2.getRainfall("42_17")
        #expect(result?.count == 1)
        #expect(result?.first?.amount == 8.0)

        // Clean up
        await cache2._resetForTesting()
    }
}
