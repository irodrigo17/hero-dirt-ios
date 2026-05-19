import Foundation
import Testing

@testable import HeroDirt

@Suite(.serialized)
struct WeatherCacheTests {

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Rainfall cache

    @Test func rainfallCacheMissReturnsNil() async {
        let cache = WeatherCache(directory: makeTempDir())
        #expect(await cache.getRainfall("0_0") == nil)
    }

    @Test func rainfallCacheHitReturnsValue() async {
        let cache = WeatherCache(directory: makeTempDir())
        let daily = [DailyWeatherData(date: Date(), amount: 12.5, et0: 3.0)]
        await cache.setRainfall("10_20", daily)
        let result = await cache.getRainfall("10_20")
        #expect(result?.count == 1)
        #expect(result?.first?.amount == 12.5)
        #expect(result?.first?.et0 == 3.0)
    }

    @Test func rainfallDifferentKeysMiss() async {
        let cache = WeatherCache(directory: makeTempDir())
        let daily = [DailyWeatherData(date: Date(), amount: 5.0, et0: 1.0)]
        await cache.setRainfall("10_20", daily)
        #expect(await cache.getRainfall("10_21") == nil)
    }

    @Test func rainfallExpiredEntryReturnsNil() async {
        let dir = makeTempDir()
        let key = "10_20"
        let old = WeatherCache.Entry(
            value: [DailyWeatherData(date: Date(), amount: 5.0, et0: 1.0)],
            timestamp: Date(timeIntervalSinceNow: -WeatherCache.rainfallTTL - 1)
        )
        let expired: [String: WeatherCache.Entry<[DailyWeatherData]>] = [key: old]
        if let data = try? JSONEncoder().encode(expired) {
            try? data.write(to: dir.appending(path: "hero_dirt_rainfall.json"), options: .atomic)
        }
        let cache = WeatherCache(directory: dir)
        #expect(await cache.getRainfall(key) == nil)
    }

    // MARK: - Forecast cache

    @Test func forecastCacheMissReturnsNil() async {
        let cache = WeatherCache(directory: makeTempDir())
        #expect(await cache.getForecast("0_0") == nil)
    }

    @Test func forecastCacheHitReturnsValue() async {
        let cache = WeatherCache(directory: makeTempDir())
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

    @Test func rainfallPersistedToDiskAndLoadedByNewInstance() async {
        let dir = makeTempDir()
        let cache = WeatherCache(directory: dir)
        let daily = [DailyWeatherData(date: Date(), amount: 8.0, et0: 2.5)]
        await cache.setRainfall("42_17", daily)

        let task = await cache.persistTask
        await task?.value

        let cache2 = WeatherCache(directory: dir)
        let result = await cache2.getRainfall("42_17")
        #expect(result?.count == 1)
        #expect(result?.first?.amount == 8.0)
    }
}
