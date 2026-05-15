import Foundation
import SwiftUI

enum DirtCondition {
    case veryWet
    case wet
    case heroDirt
    case dry
    case veryDry

    var label: String {
        switch self {
        case .veryWet: return "Very Wet"
        case .wet: return "Wet"
        case .heroDirt: return "Hero Dirt"
        case .dry: return "Dry"
        case .veryDry: return "Very Dry"
        }
    }

    var icon: String {
        switch self {
        case .veryWet: return "drop.circle.fill"
        case .wet: return "drop.fill"
        case .heroDirt: return "sparkles"
        case .dry: return "sun.max.fill"
        case .veryDry: return "sun.horizon.fill"
        }
    }

    var color: Color {
        switch self {
        case .veryWet: return .indigo
        case .wet: return .blue
        case .heroDirt: return .green
        case .dry: return .orange
        case .veryDry: return .red
        }
    }

    var description: String {
        switch self {
        case .veryWet: return "Trails are flooded or deeply muddy"
        case .wet: return "Trails are likely muddy"
        case .heroDirt: return "Perfect conditions"
        case .dry: return "Trails may be loose or dusty"
        case .veryDry: return "Trails are very dry and loose"
        }
    }
}

struct RainForecast: Sendable {
    let next1Day: Double
    let next2Days: Double
    let next3Days: Double
    let next7Days: Double
}

struct DailyWeatherData: Sendable {
    let date: Date
    let amount: Double   // precipitation in mm
    let et0: Double      // FAO Penman-Monteith reference ET in mm/day

    init(date: Date, amount: Double, et0: Double = 0) {
        self.date = date
        self.amount = amount
        self.et0 = et0
    }
}

typealias DailyRainfall = DailyWeatherData

struct RainfallSummary: Sendable {
    let last1Day: Double
    let last2Days: Double
    let last3Days: Double
    let last7Days: Double
    let daysSinceLastRain: Int?
    let dailyHistory: [DailyWeatherData]   // sorted newest-first

    private static let mmPerInch = 25.4
    private static let heroDirtBufferDays = 3.0

    init(
        last1Day: Double,
        last2Days: Double,
        last3Days: Double,
        last7Days: Double,
        daysSinceLastRain: Int?,
        dailyHistory: [DailyWeatherData] = []
    ) {
        self.last1Day = last1Day
        self.last2Days = last2Days
        self.last3Days = last3Days
        self.last7Days = last7Days
        self.daysSinceLastRain = daysSinceLastRain
        self.dailyHistory = dailyHistory
    }

    init(daily: [DailyWeatherData]) {
        let sorted = daily.sorted { $0.date > $1.date }

        last1Day = sorted.prefix(1).reduce(0) { $0 + $1.amount }
        last2Days = sorted.prefix(2).reduce(0) { $0 + $1.amount }
        last3Days = sorted.prefix(3).reduce(0) { $0 + $1.amount }
        last7Days = sorted.prefix(7).reduce(0) { $0 + $1.amount }

        daysSinceLastRain = Self.computeDaysSinceRain(sorted: sorted)
        dailyHistory = sorted
    }

    // MARK: - Dirt Condition

    func dirtCondition(soil: SoilData? = nil) -> DirtCondition {
        guard dailyHistory.contains(where: { $0.et0 > 0 }) else {
            return legacyDirtCondition
        }

        let resolvedSoil = soil ?? .loam
        var moisture = resolvedSoil.fieldCapacity * 0.4

        for day in dailyHistory.reversed() {
            moisture = min(moisture + day.amount, resolvedSoil.fieldCapacity)
            let actualET = day.et0 * (moisture / resolvedSoil.fieldCapacity) * resolvedSoil.dryingRate
            moisture = max(0, moisture - actualET)
        }

        let index = moisture / resolvedSoil.fieldCapacity
        switch index {
        case let x where x > 0.80: return .veryWet
        case let x where x > 0.60: return .wet
        case let x where x >= 0.25: return .heroDirt
        case let x where x >= 0.10: return .dry
        default: return .veryDry
        }
    }

    private var legacyDirtCondition: DirtCondition {
        let daysSince = Double(daysSinceLastRain ?? 30)
        let requiredDays = max(1.0, last7Days / Self.mmPerInch)
        if daysSince < requiredDays { return .wet }
        if daysSince <= requiredDays + Self.heroDirtBufferDays { return .heroDirt }
        return .dry
    }

    private static func computeDaysSinceRain(sorted: [DailyWeatherData]) -> Int? {
        for (index, day) in sorted.enumerated() {
            if day.amount > 0.1 {
                return index
            }
        }
        return nil
    }
}
