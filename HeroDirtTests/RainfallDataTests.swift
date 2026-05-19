import Foundation
import Testing

@testable import HeroDirt

struct RainfallDataTests {

    // MARK: - RainfallSummary from daily data

    @Test func summaryPrefixSums() {
        let today = Date()
        let daily = (0..<7).map { i in
            DailyWeatherData(
                date: Calendar.current.date(
                    byAdding: .day,
                    value: -i,
                    to: today
                )!,
                amount: Double(i + 1)
            )
        }
        let summary = RainfallSummary(daily: daily)

        #expect(summary.last1Day == 1)
        #expect(summary.last2Days == 3)  // 1+2
        #expect(summary.last3Days == 6)  // 1+2+3
        #expect(summary.last7Days == 28)  // 1+2+3+4+5+6+7
    }

    @Test func emptyDailyArray() {
        let summary = RainfallSummary(daily: [])

        #expect(summary.last1Day == 0)
        #expect(summary.last2Days == 0)
        #expect(summary.last3Days == 0)
        #expect(summary.last7Days == 0)
        #expect(summary.daysSinceLastRain == nil)
    }

    @Test func unsortedInputStillCorrect() {
        let today = Date()
        // Deliberately out of order
        let daily = [
            DailyWeatherData(
                date: Calendar.current.date(
                    byAdding: .day,
                    value: -2,
                    to: today
                )!,
                amount: 10
            ),
            DailyWeatherData(
                date: Calendar.current.date(
                    byAdding: .day,
                    value: 0,
                    to: today
                )!,
                amount: 1
            ),
            DailyWeatherData(
                date: Calendar.current.date(
                    byAdding: .day,
                    value: -1,
                    to: today
                )!,
                amount: 5
            ),
        ]
        let summary = RainfallSummary(daily: daily)

        // Sorted descending by date: today(1), yesterday(5), 2-days-ago(10)
        #expect(summary.last1Day == 1)
        #expect(summary.last2Days == 6)
        #expect(summary.last3Days == 16)
    }

    // MARK: - daysSinceLastRain

    @Test func daysSinceRainToday() {
        let today = Date()
        let daily = [
            DailyWeatherData(date: today, amount: 5.0),
            DailyWeatherData(
                date: Calendar.current.date(
                    byAdding: .day,
                    value: -1,
                    to: today
                )!,
                amount: 0.0
            ),
        ]
        let summary = RainfallSummary(daily: daily)
        #expect(summary.daysSinceLastRain == 0)
    }

    @Test func daysSinceRainThreeDaysAgo() {
        let today = Date()
        let daily = [
            DailyWeatherData(date: today, amount: 0.0),
            DailyWeatherData(
                date: Calendar.current.date(
                    byAdding: .day,
                    value: -1,
                    to: today
                )!,
                amount: 0.0
            ),
            DailyWeatherData(
                date: Calendar.current.date(
                    byAdding: .day,
                    value: -2,
                    to: today
                )!,
                amount: 0.0
            ),
            DailyWeatherData(
                date: Calendar.current.date(
                    byAdding: .day,
                    value: -3,
                    to: today
                )!,
                amount: 5.0
            ),
        ]
        let summary = RainfallSummary(daily: daily)
        #expect(summary.daysSinceLastRain == 3)
    }

    @Test func daysSinceRainNone() {
        let today = Date()
        let daily = [
            DailyWeatherData(date: today, amount: 0.0),
            DailyWeatherData(
                date: Calendar.current.date(
                    byAdding: .day,
                    value: -1,
                    to: today
                )!,
                amount: 0.05
            ),
        ]
        let summary = RainfallSummary(daily: daily)
        #expect(summary.daysSinceLastRain == nil)
    }

    // MARK: - DirtCondition

    @Test func dirtConditionWetRainedToday() {
        // 25mm today → requiredDays≈1, daysSince=0 → wet
        let summary = RainfallSummary(
            last1Day: 25,
            last2Days: 25,
            last3Days: 25,
            last7Days: 25,
            daysSinceLastRain: 0
        )
        #expect(summary.dirtCondition() == .wet)
    }

    @Test func dirtConditionHeroDirtAfterModerateRain() {
        // 25mm two days ago → requiredDays≈1, daysSince=2 ∈ [1, 4] → hero dirt
        let summary = RainfallSummary(
            last1Day: 0,
            last2Days: 0,
            last3Days: 25,
            last7Days: 25,
            daysSinceLastRain: 2
        )
        #expect(summary.dirtCondition() == .heroDirt)
    }

    @Test func dirtConditionDryAfterModerateRain() {
        // 25mm six days ago → requiredDays≈1, daysSince=6 > 4 → dry
        let summary = RainfallSummary(
            last1Day: 0,
            last2Days: 0,
            last3Days: 0,
            last7Days: 25,
            daysSinceLastRain: 6
        )
        #expect(summary.dirtCondition() == .dry)
    }

    @Test func dirtConditionHeroDirtAfterHeavyRain() {
        // 100mm five days ago → requiredDays≈3.9, daysSince=5 ∈ [3.9, 6.9] → hero dirt
        let summary = RainfallSummary(
            last1Day: 0,
            last2Days: 0,
            last3Days: 0,
            last7Days: 100,
            daysSinceLastRain: 5
        )
        #expect(summary.dirtCondition() == .heroDirt)
    }

    @Test func dirtConditionDryNoRecentRain() {
        // No rain in 30+ days → dry
        let summary = RainfallSummary(
            last1Day: 0,
            last2Days: 0,
            last3Days: 0,
            last7Days: 0,
            daysSinceLastRain: nil
        )
        #expect(summary.dirtCondition() == .dry)
    }

    @Test func dirtConditionWetHeavyRainStillDrying() {
        // 100mm two days ago → requiredDays≈3.9, daysSince=2 < 3.9 → wet
        let summary = RainfallSummary(
            last1Day: 0,
            last2Days: 0,
            last3Days: 100,
            last7Days: 100,
            daysSinceLastRain: 2
        )
        #expect(summary.dirtCondition() == .wet)
    }

    // MARK: - Threshold boundary

    @Test func thresholdBoundary() {
        let today = Date()
        // 0.1mm is NOT considered rain (threshold is > 0.1)
        let dailyAt01 = [DailyWeatherData(date: today, amount: 0.1)]
        #expect(RainfallSummary(daily: dailyAt01).daysSinceLastRain == nil)

        // 0.11mm IS considered rain
        let dailyAbove = [DailyWeatherData(date: today, amount: 0.11)]
        #expect(RainfallSummary(daily: dailyAbove).daysSinceLastRain == 0)
    }

    // MARK: - Sendable conformance

    @Test func summarySendable() {
        let summary = RainfallSummary(
            last1Day: 1,
            last2Days: 2,
            last3Days: 3,
            last7Days: 7,
            daysSinceLastRain: 1
        )

        func checkSendable(_: some Sendable) {}
        checkSendable(summary)
    }

    @Test func forecastSendable() {
        let forecast = RainForecast(
            next1Day: 1,
            next2Days: 2,
            next3Days: 3,
            next7Days: 7
        )

        func checkSendable(_: some Sendable) {}
        checkSendable(forecast)
    }

    @Test func dailyWeatherDataSendable() {
        let daily = DailyWeatherData(date: Date(), amount: 5.0)

        func checkSendable(_: some Sendable) {}
        checkSendable(daily)
    }
}
