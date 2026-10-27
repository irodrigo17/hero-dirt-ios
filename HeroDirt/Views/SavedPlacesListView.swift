import MapKit
import SwiftUI

struct SavedPlacesListView: View {
    @Environment(PlaceStore.self) private var placeStore
    @Environment(\.weather) private var weather
    var onSelectPlace: (Place) -> Void = { _ in }
    var selectedDetent: PresentationDetent

    @Environment(PlaceConditionsModel.self) private var conditions
    var body: some View { content }

    @ViewBuilder
    private var content: some View {
        if placeStore.places.isEmpty {
            ContentUnavailableView(
                "No trails yet",
                systemImage: "bicycle",
                description: Text(
                    "Search for a trail or park, tap a spot on the map, or long-press to drop a pin. Then tap Save to keep an eye on it here."
                )
            )
        } else {
            List {
                ForEach(placeStore.places) { place in
                    Button {
                        onSelectPlace(place)
                    } label: {
                        HStack(spacing: 8) {
                            TrailCard(
                                place: place,
                                rainfall: conditions.rainfall[place.id],
                                isLoading: conditions.loading.contains(place.id),
                                error: conditions.errors[place.id]
                            )
                            Image(systemName: "chevron.forward")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .leading) {
                        Button {
                            DrivingDirections.open(to: place)
                        } label: {
                            Label("Directions", systemImage: "car.fill")
                        }
                        .accessibilityHint("Opens directions in your default navigation app")
                        .tint(.blue)
                    }
                }
                .onDelete { offsets in
                    placeStore.removePlaces(at: offsets)
                }
            }
            .listStyle(.plain)
            .refreshable {
                await conditions.refresh(placeStore.places, weather: weather)
            }
        }
    }
}

#Preview("Saved places") {
    NavigationStack {
        SavedPlacesListView(selectedDetent: .large)
            .navigationTitle("My Trails")
            .navigationBarTitleDisplayMode(.inline)
    }
    .previewEnvironment()
}

#Preview("Empty") {
    SavedPlacesListView(selectedDetent: .large)
        .previewEnvironment(store: SampleData.placeStore([]))
}
