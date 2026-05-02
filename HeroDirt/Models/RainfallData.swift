import Foundation

struct DailyRainfall {
    let date: Date
    let amount: Double // millimeters
}

struct RainfallSummary {
    let last1Day: Double
    let last2Days: Double
    let last3Days: Double
    let last7Days: Double
    let daysSinceLastRain: Int? // nil = no rain in available data (~30 days)

    init(last1Day: Double, last2Days: Double, last3Days: Double, last7Days: Double, daysSinceLastRain: Int?) {
        self.last1Day = last1Day
        self.last2Days = last2Days
        self.last3Days = last3Days
        self.last7Days = last7Days
        self.daysSinceLastRain = daysSinceLastRain
    }

    init(daily: [DailyRainfall]) {
        let sorted = daily.sorted { $0.date > $1.date }

        last1Day = sorted.prefix(1).reduce(0) { $0 + $1.amount }
        last2Days = sorted.prefix(2).reduce(0) { $0 + $1.amount }
        last3Days = sorted.prefix(3).reduce(0) { $0 + $1.amount }
        last7Days = sorted.prefix(7).reduce(0) { $0 + $1.amount }

        daysSinceLastRain = Self.computeDaysSinceRain(sorted: sorted)
    }

    private static func computeDaysSinceRain(sorted: [DailyRainfall]) -> Int? {
        for (index, day) in sorted.enumerated() {
            if day.amount > 0.1 {
                return index
            }
        }
        return nil
    }
}
