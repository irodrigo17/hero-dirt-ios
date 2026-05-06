import SwiftUI

struct RainForecastCardView: View {
    let forecast: RainForecast

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Rain Forecast")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text("Next days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                forecastTile("1 day", value: forecast.next1Day)
                forecastTile("2 days", value: forecast.next2Days)
                forecastTile("3 days", value: forecast.next3Days)
                forecastTile("7 days", value: forecast.next7Days)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func forecastTile(_ label: String, value: Double) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(formatMM(value))
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(.blue)
            Text("mm")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(value > 0 ? Color.blue.opacity(0.08) : Color.gray.opacity(0.06),
                     in: RoundedRectangle(cornerRadius: 8))
    }

    private func formatMM(_ value: Double) -> String {
        value < 10 ? String(format: "%.1f", value) : String(format: "%.0f", value)
    }
}
