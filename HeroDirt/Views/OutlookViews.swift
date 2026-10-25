import Charts
import SwiftUI

/// "The week ahead": when it'll be ridable plus a day-by-day strip.
struct OutlookCardView: View {
    let current: DirtCondition
    let days: [DayCondition]  // today + forecast days

    var body: some View {
        CardContainer {
            CardHeader(title: "The Week Ahead", subtitle: "Estimate")
            if let text = OutlookSummary.text(current: current, upcoming: days.filter(\.isForecast)) {
                Text(text)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ConditionStrip(days: days, style: .large)
        }
    }
}

/// Wetness over the last two weeks and the forecast week, with the hero dirt
/// band, and daily rain underneath.
struct ConditionTrendView: View {
    let timeline: [DayCondition]

    @Environment(\.rainUnit) private var unit

    private static let heroBand = 0.25...0.60

    var body: some View {
        CardContainer {
            CardHeader(title: "Wetness Trend", subtitle: "2 weeks + forecast")

            Chart {
                RectangleMark(
                    yStart: .value(String(localized: "Low"), Self.heroBand.lowerBound * 100),
                    yEnd: .value(String(localized: "High"), Self.heroBand.upperBound * 100)
                )
                .foregroundStyle(DirtCondition.heroDirt.color.opacity(0.14))
                .annotation(position: .overlay, alignment: .topLeading) {
                    Text("Hero dirt")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(DirtCondition.heroDirt.color)
                        .padding(4)
                }

                ForEach(timeline) { day in
                    LineMark(
                        x: .value(String(localized: "Day"), day.date, unit: .day),
                        y: .value(String(localized: "Wetness"), day.moistureIndex * 100),
                        series: .value(String(localized: "Kind"), day.isForecast ? String(localized: "Forecast") : String(localized: "Observed"))
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(day.isForecast ? Color.secondary : Color.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, dash: day.isForecast ? [5, 4] : []))
                }

                // Today: a dashed rule and a dot in the current condition's
                // color; the dashed line after it is the forecast.
                if let lastObserved = timeline.last(where: { !$0.isForecast }) {
                    RuleMark(x: .value(String(localized: "Day"), lastObserved.date, unit: .day))
                        .foregroundStyle(Color.secondary.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    PointMark(
                        x: .value(String(localized: "Day"), lastObserved.date, unit: .day),
                        y: .value(String(localized: "Wetness"), lastObserved.moistureIndex * 100)
                    )
                    .foregroundStyle(lastObserved.condition.color)
                    .symbolSize(70)
                }
            }
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(values: [0, 50, 100]) { value in
                    AxisGridLine()
                    AxisValueLabel(anchor: .leading) {
                        if let v = value.as(Int.self) {
                            Text(v == 0 ? String(localized: "Dry") : v == 100 ? String(localized: "Soaked") : "")
                        }
                    }
                }
            }
            .chartXAxis(.hidden)
            .frame(height: 140)
            .accessibilityLabel("Wetness over the last two weeks and the next week")

            Chart(timeline) { day in
                BarMark(
                    x: .value(String(localized: "Day"), day.date, unit: .day),
                    y: .value(String(localized: "Rain"), day.rain)
                )
                .foregroundStyle(day.isForecast ? Color.blue.opacity(0.35) : Color.blue)
                .cornerRadius(2)
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 2)) { value in
                    AxisGridLine()
                    AxisValueLabel(anchor: .leading) {
                        if let mm = value.as(Double.self) {
                            Text(unit.formatWithUnit(mm))
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day(), anchor: .top)
                }
            }
            .frame(height: 70)
            .accessibilityLabel("Daily rain")
        }
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            OutlookCardView(current: .wet, days: SampleData.muddy.strip(soil: SampleData.loam))
            ConditionTrendView(timeline: SampleData.muddy.timeline(soil: SampleData.loam))
        }
        .padding()
    }
}
