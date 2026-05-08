import SwiftUI

struct RainfallCardView: View {
    let summary: RainfallSummary

    var body: some View {
        VStack(spacing: 16) {
            CardHeader(title: "Rainfall", subtitle: "Past days")

            HStack(spacing: 10) {
                rainfallTile("1 day", value: summary.last1Day)
                rainfallTile("2 days", value: summary.last2Days)
                rainfallTile("3 days", value: summary.last3Days)
                rainfallTile("7 days", value: summary.last7Days)
            }

            Divider()

            HStack {
                Image(systemName: "cloud.rain")
                    .foregroundStyle(.blue)
                Text("Last rain:")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(lastRainText)
                    .fontWeight(.semibold)
            }
            .font(.subheadline)
        }
        .padding()
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: .cornerMedium)
        )
    }

    private var lastRainText: String {
        guard let days = summary.daysSinceLastRain else {
            return "30+ days ago"
        }
        switch days {
        case 0: return "Today"
        case 1: return "Yesterday"
        default: return "\(days) days ago"
        }
    }

    private func rainfallTile(_ label: String, value: Double) -> some View {
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
        .background(
            value > 0 ? Color.blue.opacity(0.08) : Color.gray.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }
}
