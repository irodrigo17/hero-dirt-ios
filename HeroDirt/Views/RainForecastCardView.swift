import SwiftUI

struct RainForecastCardView: View {
    let forecast: RainForecast

    var body: some View {
        VStack(spacing: 16) {
            CardHeader(title: "Rain Forecast", subtitle: "Next days")

            HStack(spacing: 10) {
                forecastTile("1 day", value: forecast.next1Day)
                forecastTile("2 days", value: forecast.next2Days)
                forecastTile("3 days", value: forecast.next3Days)
                forecastTile("7 days", value: forecast.next7Days)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: .cornerMedium))
    }

    private func forecastTile(_ label: String, value: Double) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value.formatMillimeters())
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
}
