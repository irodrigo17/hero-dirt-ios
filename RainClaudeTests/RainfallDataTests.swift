import Testing
import Foundation
@testable import RainClaude

struct RainfallDataTests {

    // MARK: - RainfallSummary from daily data

    @Test func summaryPrefixSums() {
        let today = Date()
        let daily = (0..<7).map { i in
            DailyRainfall(
                date: Calendar.current.date(byAdding: .day, value: -i, to: today)!,
                amount: Double(i + 1)
            )
        }
        let summary = RainfallSummary(daily: daily)

        #expect(summary.last1Day == 1)
        #expect(summary.last2Days == 3)   // 1+2
        #expect(summary.last3Days == 6)   // 1+2+3
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
            DailyRainfall(date: Calendar.current.date(byAdding: .day, value: -2, to: today)!, amount: 10),
            DailyRainfall(date: Calendar.current.date(byAdding: .day, value: 0, to: today)!, amount: 1),
            DailyRainfall(date: Calendar.current.date(byAdding: .day, value: -1, to: today)!, amount: 5),
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
            DailyRainfall(date: today, amount: 5.0),
            DailyRainfall(date: Calendar.current.date(byAdding: .day, value: -1, to: today)!, amount: 0.0),
        ]
        let summary = RainfallSummary(daily: daily)
        #expect(summary.daysSinceLastRain == 0)
    }

    @Test func daysSinceRainThreeDaysAgo() {
        let today = Date()
        let daily = [
            DailyRainfall(date: today, amount: 0.0),
            DailyRainfall(date: Calendar.current.date(byAdding: .day, value: -1, to: today)!, amount: 0.0),
            DailyRainfall(date: Calendar.current.date(byAdding: .day, value: -2, to: today)!, amount: 0.0),
            DailyRainfall(date: Calendar.current.date(byAdding: .day, value: -3, to: today)!, amount: 5.0),
        ]
        let summary = RainfallSummary(daily: daily)
        #expect(summary.daysSinceLastRain == 3)
    }

    @Test func daysSinceRainNone() {
        let today = Date()
        let daily = [
            DailyRainfall(date: today, amount: 0.0),
            DailyRainfall(date: Calendar.current.date(byAdding: .day, value: -1, to: today)!, amount: 0.05),
        ]
        let summary = RainfallSummary(daily: daily)
        #expect(summary.daysSinceLastRain == nil)
    }

    // MARK: - Threshold boundary

    @Test func thresholdBoundary() {
        let today = Date()
        // 0.1mm is NOT considered rain (threshold is > 0.1)
        let dailyAt01 = [DailyRainfall(date: today, amount: 0.1)]
        #expect(RainfallSummary(daily: dailyAt01).daysSinceLastRain == nil)

        // 0.11mm IS considered rain
        let dailyAbove = [DailyRainfall(date: today, amount: 0.11)]
        #expect(RainfallSummary(daily: dailyAbove).daysSinceLastRain == 0)
    }
}
