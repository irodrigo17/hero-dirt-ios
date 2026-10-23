import Foundation
import Testing

@testable import HeroDirt

struct OutlookTests {

    private let calendar = Calendar.current
    private var today: Date { calendar.startOfDay(for: Date()) }

    private func summary(history: [Double], forecast: [Double], et0: Double = 3) -> RainfallSummary {
        let past = history.enumerated().map { i, rain in
            DailyWeatherData(date: calendar.date(byAdding: .day, value: -i, to: today)!, amount: rain, et0: et0)
        }
        let future = forecast.enumerated().map { i, rain in
            DailyWeatherData(date: calendar.date(byAdding: .day, value: i + 1, to: today)!, amount: rain, et0: et0, isForecast: true)
        }
        return RainfallSummary(daily: past + future)
    }

    private func day(_ offset: Int, _ condition: DirtCondition) -> DayCondition {
        DayCondition(
            date: calendar.date(byAdding: .day, value: offset, to: today)!,
            rain: 0, moistureIndex: 0.5, condition: condition, isForecast: true
        )
    }

    // MARK: - Model

    @Test func timelineHasHistoryThenForecast() {
        let s = summary(history: Array(repeating: 0, count: 30), forecast: [0, 0, 5, 0, 0, 0, 0])
        let timeline = s.timeline(historyDays: 14)
        #expect(timeline.count == 21)
        #expect(timeline.prefix(14).allSatisfy { !$0.isForecast })
        #expect(timeline.suffix(7).allSatisfy { $0.isForecast })
        #expect(timeline.map(\.date) == timeline.map(\.date).sorted())
    }

    @Test func todayMatchesCurrentCondition() {
        let s = summary(history: [0, 0, 18, 6] + Array(repeating: 0, count: 26), forecast: [0, 0, 0])
        let todayCondition = s.timeline().last { !$0.isForecast }?.condition
        #expect(todayCondition == s.dirtCondition())
    }

    @Test func dryingForwardAfterRainReachesHeroDirt() {
        // Soaked today, dry week ahead: the outlook should dry out.
        let s = summary(history: [25, 10] + Array(repeating: 0, count: 28), forecast: Array(repeating: 0, count: 7), et0: 4)
        let outlook = s.outlook()
        #expect(outlook.count == 7)
        #expect(outlook.first!.moistureIndex > outlook.last!.moistureIndex)
        #expect(outlook.contains { $0.condition.wetness <= DirtCondition.heroDirt.wetness })
    }

    @Test func forecastRainMakesItMuddy() {
        let s = summary(history: Array(repeating: 0, count: 30), forecast: [0, 0, 20, 0])
        let outlook = s.outlook()
        #expect(outlook[2].condition.wetness >= DirtCondition.wet.wetness)
    }

    @Test func noET0MeansNoOutlook() {
        let s = summary(history: Array(repeating: 0, count: 10), forecast: [0, 0], et0: 0)
        #expect(s.timeline().isEmpty)
    }

    // MARK: - Summary text

    @Test func muddyNowRidableLater() {
        let text = OutlookSummary.text(current: .wet, upcoming: [day(1, .wet), day(2, .heroDirt)], today: today)
        #expect(text == "Hero dirt by \(OutlookSummary.weekday(day(2, .wet).date))")
    }

    @Test func muddyNowRidableTomorrow() {
        let text = OutlookSummary.text(current: .veryWet, upcoming: [day(1, .dry)], today: today)
        #expect(text == "Ridable by tomorrow")
    }

    @Test func muddyAllWeek() {
        let text = OutlookSummary.text(current: .wet, upcoming: (1...7).map { day($0, .wet) }, today: today)
        #expect(text == "Muddy all week")
    }

    @Test func heroDirtWithRainTomorrow() {
        let text = OutlookSummary.text(current: .heroDirt, upcoming: [day(1, .wet)], today: today)
        #expect(text == "Rain tomorrow, ride today")
    }

    @Test func heroDirtAllWeek() {
        let text = OutlookSummary.text(current: .heroDirt, upcoming: (1...7).map { day($0, .heroDirt) }, today: today)
        #expect(text == "Hero dirt all week")
    }

    @Test func dryThenRain() {
        let text = OutlookSummary.text(current: .dry, upcoming: [day(1, .dry), day(2, .wet)], today: today)
        #expect(text?.hasPrefix("Rain ") == true)
    }

    @Test func noForecastNoText() {
        #expect(OutlookSummary.text(current: .dry, upcoming: [], today: today) == nil)
    }
}
