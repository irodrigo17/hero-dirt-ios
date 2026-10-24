import SwiftUI

struct RainForecastCardView: View {
    let forecast: RainForecast
    @State private var showingDailyForecast = false

    var body: some View {
        CardContainer {
            CardHeader(title: "Rain on the Way", subtitle: "Next 7 days")
            RainTilesRow(tiles: forecast.nextTiles)
            if let days = forecast.daily, !days.isEmpty {
                Button { showingDailyForecast = true } label: {
                    Label("Daily Rain Forecast", systemImage: "calendar")
                }
                .font(.subheadline)
            }
            WeatherAttributionView()
        }
        .sheet(isPresented: $showingDailyForecast) {
            DailyRainForecastView(days: forecast.daily ?? [])
        }
    }
}

#Preview {
    RainForecastCardView(forecast: SampleData.forecast)
        .padding()
}
