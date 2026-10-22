import Foundation
import Testing

@testable import HeroDirt

struct ObservedRainTests {

    /// 2026-10-22 15:30 in UTC-7.
    private let now = ISO8601DateFormatter().date(from: "2026-10-22T22:30:00Z")!

    private func response(hourlyRain: [String: Double]) -> WeatherService.OpenMeteoResponse {
        let hours = (0..<24).map { String(format: "2026-10-22T%02d:00", $0) }
        return WeatherService.OpenMeteoResponse(
            utcOffsetSeconds: -25200,
            daily: .init(
                time: ["2026-10-21", "2026-10-22", "2026-10-23"],
                precipitationSum: [3.0, 20.0, 9.0],
                et0FaoEvapotranspiration: [2.0, 2.4, 2.0]
            ),
            hourly: .init(
                time: hours,
                precipitation: hours.map { hourlyRain[$0] ?? 0 },
                et0FaoEvapotranspiration: hours.map { _ in 0.1 }
            )
        )
    }

    @Test func todayExcludesForecastHours() {
        // 2 mm fell this morning; 18 mm is forecast for tonight.
        let resp = response(hourlyRain: ["2026-10-22T09:00": 2.0, "2026-10-22T21:00": 18.0])
        let daily = WeatherService.observedDaily(from: resp, now: now)
        let summary = RainfallSummary(daily: daily)
        #expect(summary.last1Day == 2.0)
        #expect(summary.last2Days == 5.0)
    }

    @Test func todayET0OnlyCountsElapsedHours() {
        let daily = WeatherService.observedDaily(from: response(hourlyRain: [:]), now: now)
        let today = daily.max { $0.date < $1.date }!
        // Hours 00:00 through 15:00 have elapsed: 16 × 0.1.
        #expect(abs(today.et0 - 1.6) < 0.0001)
    }

    @Test func futureDaysAreDropped() {
        let daily = WeatherService.observedDaily(from: response(hourlyRain: [:]), now: now)
        #expect(daily.count == 2)
    }

    @Test func withoutHourlyFallsBackToDaily() {
        let resp = WeatherService.OpenMeteoResponse(
            utcOffsetSeconds: -25200,
            daily: .init(time: ["2026-10-22"], precipitationSum: [7.0], et0FaoEvapotranspiration: nil),
            hourly: nil
        )
        let daily = WeatherService.observedDaily(from: resp, now: now)
        #expect(daily.first?.amount == 7.0)
    }

    @Test func rollingDaysBucketsMostRecentFirst() {
        // 48 hours: 1 mm/h in the older day, 0.5 mm/h in the last 24h.
        let values: [Double?] = Array(repeating: 1.0, count: 24) + Array(repeating: 0.5, count: 24)
        let hourly = WeatherService.HourlyData(
            time: values.indices.map { "h\($0)" }, precipitation: values, et0FaoEvapotranspiration: nil
        )
        let summary = RainfallSummary(daily: WeatherService.rollingDays(from: hourly, now: now))
        #expect(summary.last1Day == 12.0)
        #expect(summary.last2Days == 36.0)
    }
}
