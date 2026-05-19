import Foundation
import Testing

@testable import HeroDirt

struct RainForecastTests {

    @Test func allPrefixSums() {
        let forecast = RainForecast(
            next1Day: 1,
            next2Days: 3,
            next3Days: 6,
            next7Days: 28
        )

        #expect(forecast.next1Day == 1)
        #expect(forecast.next2Days == 3)
        #expect(forecast.next3Days == 6)
        #expect(forecast.next7Days == 28)
    }

    @Test func zeroForecast() {
        let forecast = RainForecast(
            next1Day: 0,
            next2Days: 0,
            next3Days: 0,
            next7Days: 0
        )

        #expect(forecast.next1Day == 0)
        #expect(forecast.next2Days == 0)
        #expect(forecast.next3Days == 0)
        #expect(forecast.next7Days == 0)
    }

    @Test func heavyRainForecast() {
        let forecast = RainForecast(
            next1Day: 50,
            next2Days: 75,
            next3Days: 100,
            next7Days: 150
        )

        #expect(forecast.next1Day < forecast.next2Days)
        #expect(forecast.next2Days < forecast.next3Days)
        #expect(forecast.next3Days < forecast.next7Days)
    }
}

struct DailyWeatherDataTests {

    @Test func dailyWeatherDataInit() {
        let date = Date()
        let daily = DailyWeatherData(date: date, amount: 5.5)

        #expect(daily.date == date)
        #expect(daily.amount == 5.5)
    }

    @Test func zeroAmount() {
        let date = Date()
        let daily = DailyWeatherData(date: date, amount: 0)

        #expect(daily.amount == 0)
    }
}
