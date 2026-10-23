import SwiftUI

struct ContentView: View {
    @Environment(PlaceStore.self) private var placeStore
    @Environment(PlaceConditionsModel.self) private var conditions
    @Environment(\.weather) private var weather
    @Environment(\.soil) private var soil

    var body: some View {
        MapView()
            // Conditions are shared by the list and the map pins.
            .task(id: placeStore.places.map(\.id)) {
                conditions.backfillSoil(placeStore.places, soil: soil, store: placeStore)
                await conditions.load(placeStore.places, weather: weather)
            }
    }
}
