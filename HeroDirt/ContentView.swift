import SwiftUI

/// Which home screen is showing: the trails list (default) or the map.
enum HomeMode: String {
    case list
    case map
}

struct ContentView: View {
    @Environment(PlaceStore.self) private var placeStore
    @Environment(PlaceConditionsModel.self) private var conditions
    @Environment(\.weather) private var weather
    @Environment(\.soil) private var soil

    @AppStorage("homeMode") private var mode: HomeMode = .list

    var body: some View {
        ZStack {
            switch mode {
            case .list:
                TrailsHomeView(onShowMap: { switchTo(.map) })
                    .transition(.opacity)
            case .map:
                MapView(onShowList: { switchTo(.list) })
                    .transition(.opacity)
            }
        }
        // Conditions are shared by the list and the map pins.
        .task(id: placeStore.places.map(\.id)) {
            conditions.backfillSoil(placeStore.places, soil: soil, store: placeStore)
            await conditions.load(placeStore.places, weather: weather)
        }
    }

    private func switchTo(_ newMode: HomeMode) {
        Telemetry.signal(.homeModeChanged, ["mode": newMode.rawValue])
        withAnimation(.easeInOut(duration: 0.25)) { mode = newMode }
    }
}
