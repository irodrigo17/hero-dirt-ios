import Foundation

/// Estimated trail condition for one day.
struct DayCondition: Identifiable, Sendable, Equatable {
    let date: Date
    /// Rain that day in mm (observed, or forecast when `isForecast`).
    let rain: Double
    /// Soil moisture at the end of the day, 0 (bone dry) to 1 (saturated).
    let moistureIndex: Double
    let condition: DirtCondition
    let isForecast: Bool

    var id: Date { date }
}

extension RainfallSummary {

    /// Runs the soil moisture model day by day over the observed history and
    /// then forward over the forecast. Returns the last `historyDays`
    /// observed days (ending today) followed by every forecast day, oldest
    /// first. Empty when there's no evapotranspiration data to drive the
    /// model.
    func timeline(soil: SoilData? = nil, historyDays: Int = 14) -> [DayCondition] {
        let history = Array(dailyHistory.reversed())  // oldest first
        guard history.contains(where: { $0.et0 > 0 }) else { return [] }

        let soil = soil ?? .loam
        var moisture = soil.fieldCapacity * 0.4
        var previousRain = 0.0
        var result: [DayCondition] = []

        for day in history + upcoming {
            moisture = min(moisture + day.amount, soil.fieldCapacity)
            let actualET = day.et0 * (moisture / soil.fieldCapacity) * soil.dryingRate
            moisture = max(0, moisture - actualET)

            let index = moisture / soil.fieldCapacity
            var condition = DirtCondition(moistureIndex: index)
            // Same rule as `dirtConditionResult`: real trails are muddy during
            // and right after decent rain, whatever the daily balance says.
            if day.amount >= 4 || previousRain >= 12, condition.wetness < DirtCondition.wet.wetness {
                condition = .wet
            }
            result.append(DayCondition(
                date: day.date,
                rain: day.amount,
                moistureIndex: index,
                condition: condition,
                isForecast: day.isForecast
            ))
            previousRain = day.amount
        }

        let observed = result.filter { !$0.isForecast }.suffix(historyDays)
        return Array(observed) + result.filter(\.isForecast)
    }

    /// Forecast days only.
    func outlook(soil: SoilData? = nil) -> [DayCondition] {
        timeline(soil: soil, historyDays: 0)
    }
}

// MARK: - "When will it be ridable?"

enum OutlookSummary {

    /// One line answering "when should I ride?", e.g. "Hero dirt by Sat" or
    /// "Rain tomorrow, ride today". Nil when there's no forecast.
    static func text(
        current: DirtCondition,
        upcoming: [DayCondition],
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> String? {
        guard !upcoming.isEmpty else { return nil }
        switch current {
        case .veryWet, .wet:
            guard let ridable = upcoming.first(where: { $0.condition.wetness <= DirtCondition.heroDirt.wetness }) else {
                return String(localized: "Muddy all week")
            }
            if ridable.condition == .heroDirt {
                return isTomorrow(ridable.date, today: today, calendar: calendar)
                    ? String(localized: "Hero dirt by tomorrow")
                    : String(localized: "Hero dirt by \(weekday(ridable.date))")
            }
            return isTomorrow(ridable.date, today: today, calendar: calendar)
                ? String(localized: "Ridable by tomorrow")
                : String(localized: "Ridable by \(weekday(ridable.date))")

        case .heroDirt:
            if let wet = upcoming.first(where: { $0.condition.wetness >= DirtCondition.wet.wetness }) {
                return isTomorrow(wet.date, today: today, calendar: calendar)
                    ? String(localized: "Rain tomorrow, ride today")
                    : String(localized: "Ride before \(weekday(wet.date))'s rain")
            }
            if let dry = upcoming.first(where: { $0.condition.wetness < DirtCondition.heroDirt.wetness }) {
                return isTomorrow(dry.date, today: today, calendar: calendar)
                    ? String(localized: "Drying out by tomorrow")
                    : String(localized: "Drying out by \(weekday(dry.date))")
            }
            return String(localized: "Hero dirt all week")

        case .dry, .veryDry:
            let hero = upcoming.firstIndex { $0.condition == .heroDirt }
            let wet = upcoming.firstIndex { $0.condition.wetness >= DirtCondition.wet.wetness }
            switch (hero, wet) {
            case let (h?, w?) where h < w:
                return heroText(for: upcoming[h], today: today, calendar: calendar)
            case let (_, w?):
                return isTomorrow(upcoming[w].date, today: today, calendar: calendar)
                    ? String(localized: "Rain tomorrow, hero dirt after")
                    : String(localized: "Rain \(weekday(upcoming[w].date)), hero dirt after")
            case let (h?, nil):
                return heroText(for: upcoming[h], today: today, calendar: calendar)
            case (nil, nil):
                return current == .veryDry ? String(localized: "Dusty all week") : String(localized: "Dry all week")
            }
        }
    }

    private static func heroText(for day: DayCondition, today: Date, calendar: Calendar) -> String {
        isTomorrow(day.date, today: today, calendar: calendar)
            ? String(localized: "Hero dirt tomorrow")
            : String(localized: "Hero dirt \(weekday(day.date))")
    }

    static func isTomorrow(_ date: Date, today: Date, calendar: Calendar) -> Bool {
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: today)) else {
            return false
        }
        return calendar.isDate(date, inSameDayAs: tomorrow)
    }

    static func weekday(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide))
    }
}
