import Foundation
import SwiftUI

enum DirtCondition {
    case wet
    case heroDirt
    case dry

    var label: String {
        switch self {
        case .wet: return "Wet"
        case .heroDirt: return "Hero Dirt"
        case .dry: return "Dry"
        }
    }

    var icon: String {
        switch self {
        case .wet: return "drop.fill"
        case .heroDirt: return "sparkles"
        case .dry: return "sun.max.fill"
        }
    }

    var color: Color {
        switch self {
        case .wet: return .blue
        case .heroDirt: return .green
        case .dry: return .orange
        }
    }

    var description: String {
        switch self {
        case .wet: return "Trails are likely muddy"
        case .heroDirt: return "Perfect conditions"
        case .dry: return "Trails may be loose or dusty"
        }
    }
}

struct RainForecast: Sendable {
    let next1Day: Double
    let next2Days: Double
    let next3Days: Double
    let next7Days: Double
}

struct DailyRainfall: Sendable {
    let date: Date
    let amount: Double
}

struct RainfallSummary: Sendable {
    let last1Day: Double
    let last2Days: Double
    let last3Days: Double
    let last7Days: Double
    let daysSinceLastRain: Int?

    private static let mmPerInch = 25.4
    private static let heroDirtBufferDays = 3.0

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

    var dirtCondition: DirtCondition {
        let daysSince = Double(daysSinceLastRain ?? 30)
        let requiredDays = max(1.0, last7Days / Self.mmPerInch)
        if daysSince < requiredDays { return .wet }
        if daysSince <= requiredDays + Self.heroDirtBufferDays { return .heroDirt }
        return .dry
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
