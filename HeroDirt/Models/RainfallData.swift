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
        case .veryWet: return String(localized: "Soaked")
        case .wet: return String(localized: "Muddy")
        case .heroDirt: return String(localized: "Hero Dirt")
        case .dry: return String(localized: "Dry")
        case .veryDry: return String(localized: "Dusty")
        }
    }

    /// Condition for a soil moisture index (0 = bone dry, 1 = saturated).
    init(moistureIndex index: Double) {
        switch index {
        case let x where x > 0.80: self = .veryWet
        case let x where x > 0.60: self = .wet
        case let x where x >= 0.25: self = .heroDirt
        case let x where x >= 0.10: self = .dry
        default: self = .veryDry
        }
    }

    /// Higher is wetter; used to compare conditions.
    var wetness: Int {
        switch self {
        case .veryWet: return 4
        case .wet: return 3
        case .heroDirt: return 2
        case .dry: return 1
        case .veryDry: return 0
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
        case .veryWet: return ConditionPalette.soaked
        case .wet: return ConditionPalette.muddy
        case .heroDirt: return ConditionPalette.hero
        case .dry: return ConditionPalette.dry
        case .veryDry: return ConditionPalette.dusty
        }
    }

    var description: String {
        switch self {
        case .veryWet: return String(localized: "Puddles and peanut butter mud. Give the trails a few days.")
        case .wet: return String(localized: "Riding now can leave ruts. Give it a day or so.")
        case .heroDirt: return String(localized: "Tacky and grippy. Go ride!")
        case .dry: return String(localized: "Firm and fast, getting loose in spots.")
        case .veryDry: return String(localized: "Loose and dusty. Expect sketchy corners.")
        }
    }

    /// Short line used in compact rows.
    var shortDescription: String {
        switch self {
        case .veryWet: return String(localized: "Give it a few days")
        case .wet: return String(localized: "Likely muddy")
        case .heroDirt: return String(localized: "Go ride!")
        case .dry: return String(localized: "Firm and fast")
        case .veryDry: return String(localized: "Loose and dusty")
        }
    }
}

// MARK: - DirtConditionResult

struct DirtConditionResult: Sendable {
    let condition: DirtCondition
    let moistureIndex: Double?   // 0–1, nil when legacy algorithm was used
    let recentET0: Double?       // mm/day average (last 7 days), nil when no ET0 data
    let soil: SoilData?          // resolved soil (loam if estimated), nil when legacy
}

// MARK: - Forecast

struct RainForecast: Codable, Sendable {
    let next1Day: Double
    let next2Days: Double
    let next3Days: Double
    let next7Days: Double
    var daily: [DailyRainForecast]? = nil
}

struct DailyRainForecast: Codable, Sendable, Equatable, Identifiable {
    let date: Date
    let amount: Double
    let precipitationChance: Double?
    var id: Date { date }
}

// MARK: - Daily Data

struct DailyWeatherData: Codable, Sendable, Equatable {
    let date: Date
    let amount: Double   // precipitation in mm
    let et0: Double      // FAO Penman-Monteith reference ET in mm/day
    /// A forecast day (after today) rather than observed data.
    let isForecast: Bool

    init(date: Date, amount: Double, et0: Double = 0, isForecast: Bool = false) {
        self.date = date
        self.amount = amount
        self.et0 = et0
        self.isForecast = isForecast
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(Date.self, forKey: .date)
        amount = try c.decode(Double.self, forKey: .amount)
        et0 = try c.decodeIfPresent(Double.self, forKey: .et0) ?? 0
        isForecast = try c.decodeIfPresent(Bool.self, forKey: .isForecast) ?? false
    }
}

// MARK: - RainfallSummary

struct RainfallSummary: Sendable {
    let last1Day: Double
    let last2Days: Double
    let last3Days: Double
    let last7Days: Double
    let daysSinceLastRain: Int?
    let dailyHistory: [DailyWeatherData]   // observed days, sorted newest-first
    let upcoming: [DailyWeatherData]       // forecast days after today, oldest-first

    private static let mmPerInch = 25.4
    private static let heroDirtBufferDays = 3.0

    init(
        last1Day: Double,
        last2Days: Double,
        last3Days: Double,
        last7Days: Double,
        daysSinceLastRain: Int?,
        dailyHistory: [DailyWeatherData] = [],
        upcoming: [DailyWeatherData] = []
    ) {
        self.last1Day = last1Day
        self.last2Days = last2Days
        self.last3Days = last3Days
        self.last7Days = last7Days
        self.daysSinceLastRain = daysSinceLastRain
        self.dailyHistory = dailyHistory
        self.upcoming = upcoming
    }

    /// Builds a summary from daily data. Days flagged `isForecast` become
    /// `upcoming`; everything else is observed history.
    init(daily: [DailyWeatherData]) {
        let sorted = daily.filter { !$0.isForecast }.sorted { $0.date > $1.date }
        upcoming = daily.filter(\.isForecast).sorted { $0.date < $1.date }

        last1Day = sorted.prefix(1).reduce(0) { $0 + $1.amount }
        last2Days = sorted.prefix(2).reduce(0) { $0 + $1.amount }
        last3Days = sorted.prefix(3).reduce(0) { $0 + $1.amount }
        last7Days = sorted.prefix(7).reduce(0) { $0 + $1.amount }

        daysSinceLastRain = Self.computeDaysSinceRain(sorted: sorted)
        dailyHistory = sorted
    }

    // MARK: - Dirt Condition

    func dirtConditionResult(soil: SoilData? = nil) -> DirtConditionResult {
        let recentValues = dailyHistory.prefix(7).compactMap { $0.et0 > 0 ? $0.et0 : nil }
        let recentET0 = recentValues.isEmpty
            ? nil
            : recentValues.reduce(0, +) / Double(recentValues.count)

        guard let recentET0 else {
            return DirtConditionResult(
                condition: legacyDirtCondition,
                moistureIndex: nil,
                recentET0: nil,
                soil: nil
            )
        }

        let resolvedSoil = soil ?? .loam
        var moisture = resolvedSoil.fieldCapacity * 0.4

        for day in dailyHistory.reversed() {
            moisture = min(moisture + day.amount, resolvedSoil.fieldCapacity)
            let actualET = day.et0 * (moisture / resolvedSoil.fieldCapacity) * resolvedSoil.dryingRate
            moisture = max(0, moisture - actualET)
        }

        let index = moisture / resolvedSoil.fieldCapacity
        var condition = DirtCondition(moistureIndex: index)

        // The daily water balance can't tell that rain is falling right now:
        // after a dry spell a soaking day only brings the bucket to "Hero
        // Dirt". Real trails are muddy during and right after decent rain.
        if hasFreshRain, condition.wetness < DirtCondition.wet.wetness {
            condition = .wet
        }

        return DirtConditionResult(
            condition: condition,
            moistureIndex: index,
            recentET0: recentET0,
            soil: resolvedSoil
        )
    }

    func dirtCondition(soil: SoilData? = nil) -> DirtCondition {
        dirtConditionResult(soil: soil).condition
    }

    /// Meaningful rain today (≥ 4 mm) or a soaking yesterday (≥ 12 mm).
    var hasFreshRain: Bool {
        let today = dailyHistory.first?.amount ?? 0
        let yesterday = dailyHistory.dropFirst().first?.amount ?? 0
        return today >= 4 || yesterday >= 12
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
