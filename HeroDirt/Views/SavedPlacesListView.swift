import MapKit
import SwiftUI

struct SavedPlacesListView: View {
    @Environment(PlaceStore.self) private var placeStore
    @Environment(\.weather) private var weather
    var onSelectPlace: (Place) -> Void = { _ in }
    var selectedDetent: PresentationDetent

    @Environment(PlaceConditionsModel.self) private var conditions
    @State private var renamingPlace: Place?
    @State private var editingName = ""

    var body: some View {
        content
            .alert(
                "Rename",
                isPresented: Binding(
                    get: { renamingPlace != nil },
                    set: { if !$0 { renamingPlace = nil } }
                )
            ) {
                TextField("Name", text: $editingName)
                Button("Save") {
                    let trimmed = editingName.trimmingCharacters(in: .whitespaces)
                    if let place = renamingPlace, !trimmed.isEmpty {
                        placeStore.renamePlace(place, to: trimmed)
                    }
                    renamingPlace = nil
                }
                Button("Cancel", role: .cancel) { renamingPlace = nil }
            }
    }

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
                            editingName = place.name
                            renamingPlace = place
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
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
