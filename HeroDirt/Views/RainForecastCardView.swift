import SwiftUI

struct RainForecastCardView: View {
    let forecast: RainForecast

    var body: some View {
        CardContainer {
            CardHeader(title: "Rain on the Way", subtitle: "Next 7 days")
            RainTilesRow(tiles: forecast.nextTiles)
        }
    }
}
