import SwiftUI

struct DailyRainForecastView: View {
    let days: [DailyRainForecast]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.rainUnit) private var unit

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(days.sorted { $0.date < $1.date }) { day in
                        HStack(spacing: 12) {
                            Image(systemName: day.amount > 0 ? "cloud.rain" : "cloud.sun")
                                .foregroundStyle(.blue)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(Calendar.current.isDateInToday(day.date) ? "Today" : day.date.formatted(.dateTime.weekday(.wide)))
                                    .fontWeight(.medium)
                                Text(day.date.formatted(.dateTime.month(.abbreviated).day()))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(unit.formatWithUnit(day.amount))
                                    .monospacedDigit()
                                if let chance = day.precipitationChance {
                                    Text(chance.formatted(.percent.precision(.fractionLength(0))))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .accessibilityLabel("\(chance.formatted(.percent)) chance of precipitation")
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text("Daily rainfall")
                } footer: {
                    Text("Percentages show the chance of precipitation. Forecasts can change as new weather data arrives.")
                }
                Section {
                    WeatherAttributionView()
                }
            }
            .navigationTitle("Rain Forecast")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
