import MapKit
import SwiftUI

// MARK: - 7-day condition strip

/// Today plus the forecast days as small colored chips with weekday labels.
struct ConditionStrip: View {
    let days: [DayCondition]
    var style: Style = .compact

    enum Style { case compact, large }

    @Environment(\.rainUnit) private var unit

    var body: some View {
        HStack(spacing: style == .compact ? 4 : 6) {
            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                VStack(spacing: style == .compact ? 3 : 5) {
                    Text(label(for: day, index: index))
                        .font(style == .compact ? .caption2 : .caption)
                        .fontWeight(index == 0 ? .bold : .regular)
                        .foregroundStyle(index == 0 ? .primary : .secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    RoundedRectangle(cornerRadius: style == .compact ? 4 : 8)
                        .fill(day.condition.color.gradient)
                        .frame(height: style == .compact ? 10 : 30)
                        .overlay {
                            if style == .large {
                                Image(systemName: day.condition.icon)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                        }
                    if style == .large {
                        Text(day.rain >= 0.5 ? unit.format(day.rain) : " ")
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.blue)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityText(for: day, index: index))
            }
        }
    }

    private func label(for day: DayCondition, index: Int) -> String {
        if index == 0 && !day.isForecast { return "Now" }
        return day.date.formatted(.dateTime.weekday(style == .compact ? .narrow : .abbreviated))
    }

    private func accessibilityText(for day: DayCondition, index: Int) -> String {
        let name = index == 0 && !day.isForecast ? "Today" : day.date.formatted(.dateTime.weekday(.wide))
        var text = "\(name): \(day.condition.label)"
        if day.rain >= 0.5 { text += ", \(unit.accessibilityText(day.rain)) of rain" }
        return text
    }
}

extension RainfallSummary {
    /// Today followed by the forecast days, for the condition strip.
    func strip(soil: SoilData?) -> [DayCondition] {
        let timeline = timeline(soil: soil, historyDays: 1)
        return Array(timeline.prefix(8))
    }
}

// MARK: - Trail card

/// A row in "My Trails": condition, when it'll be ridable, and the week ahead.
struct TrailCard: View {
    let place: Place
    let category: MKPointOfInterestCategory?
    let rainfall: RainfallSummary?
    let isLoading: Bool
    let error: String?

    private var soil: SoilData? { PlaceConditionsModel.soil(for: place) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                POICategoryIcon(category: category, size: 30)
                Text(place.name)
                    .font(.headline)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if let rainfall, !isLoading {
                    ConditionBadge(condition: rainfall.dirtCondition(soil: soil))
                }
            }

            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if let rainfall, !isLoading {
                let condition = rainfall.dirtCondition(soil: soil)
                let strip = rainfall.strip(soil: soil)
                Text(headline(condition: condition, rainfall: rainfall, strip: strip))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if strip.count > 1 {
                    ConditionStrip(days: strip)
                }
            } else {
                PlaceRowSkeleton()
            }
        }
        .padding(.vertical, 8)
        .animation(.easeInOut(duration: 0.25), value: rainfall == nil)
    }

    /// "Hero dirt by Sat · last rain yesterday".
    private func headline(condition: DirtCondition, rainfall: RainfallSummary, strip: [DayCondition]) -> String {
        let outlook = OutlookSummary.text(current: condition, upcoming: strip.filter(\.isForecast))
        let lastRain = "last rain \(rainfall.lastRainText.lowercased())"
        if let outlook { return "\(outlook) · \(lastRain)" }
        return "\(condition.shortDescription) · \(lastRain)"
    }
}

#Preview("Trail cards") {
    List {
        TrailCard(place: SampleData.places[0], category: .park, rainfall: SampleData.heroDirt, isLoading: false, error: nil)
        TrailCard(place: SampleData.places[1], category: .nationalPark, rainfall: SampleData.muddy, isLoading: false, error: nil)
        TrailCard(place: SampleData.places[2], category: nil, rainfall: nil, isLoading: true, error: nil)
    }
    .listStyle(.plain)
}
