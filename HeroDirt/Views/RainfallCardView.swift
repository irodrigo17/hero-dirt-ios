import SwiftUI

struct RainfallCardView: View {
    let summary: RainfallSummary

    var body: some View {
        CardContainer {
            CardHeader(title: "Recent Rain", subtitle: "Last 7 days")

            RainTilesRow(tiles: summary.pastTiles)

            Divider()

            HStack {
                Image(systemName: "cloud.rain")
                    .foregroundStyle(.blue)
                Text("Last rain")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(summary.lastRainText)
                    .fontWeight(.semibold)
            }
            .font(.subheadline)
            .accessibilityElement(children: .combine)
        }
    }
}
