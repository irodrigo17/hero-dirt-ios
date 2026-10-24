import SwiftUI

struct RainfallCardView: View {
    let summary: RainfallSummary
    @State private var showingCalendar = false

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
            if !summary.dailyHistory.isEmpty {
                Button { showingCalendar = true } label: {
                    Label("Rain Calendar", systemImage: "calendar")
                }
                .font(.subheadline)
            }
        }
        .sheet(isPresented: $showingCalendar) {
            RainHistoryCalendarView(days: summary.dailyHistory)
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        RainfallCardView(summary: SampleData.muddy)
        RainfallCardView(summary: SampleData.heroDirt)
            .environment(\.rainUnit, .millimeters)
    }
    .padding()
}
