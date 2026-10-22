import MapKit
import SwiftUI

struct SavedPlacesListView: View {
    @Environment(PlaceStore.self) private var placeStore
    @Environment(MapItemCache.self) private var mapItemCache
    @Environment(\.weather) private var weather
    @Environment(\.soil) private var soil
    var onSelectPlace: (Place) -> Void = { _ in }
    var selectedDetent: PresentationDetent

    @State private var conditions = PlaceConditionsModel()
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
                "No saved spots yet",
                systemImage: "star",
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
                        PlaceRow(
                            place: place,
                            category: mapItemCache.items[place.id]?.pointOfInterestCategory,
                            rainfall: conditions.rainfall[place.id],
                            isLoading: conditions.loading.contains(place.id),
                            error: conditions.errors[place.id]
                        )
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
            .task(id: placeStore.places.map(\.id)) {
                conditions.backfillSoil(placeStore.places, soil: soil, store: placeStore)
                await conditions.load(placeStore.places, weather: weather)
            }
        }
    }
}

// MARK: - Place Row

private struct PlaceRow: View {
    let place: Place
    let category: MKPointOfInterestCategory?
    let rainfall: RainfallSummary?
    let isLoading: Bool
    let error: String?

    private var effectiveSoil: SoilData? {
        place.soilOverride?.asSoilData ?? place.soil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                POICategoryIcon(category: category, size: 28)
                Text(place.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }

            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if let rainfall, !isLoading {
                let condition = rainfall.dirtCondition(soil: effectiveSoil)
                // Drop the short description when the row is narrow (e.g. the
                // landscape sidebar) instead of truncating everything.
                ViewThatFits(in: .horizontal) {
                    statusLine(condition: condition, rainfall: rainfall, showDescription: true)
                    statusLine(condition: condition, rainfall: rainfall, showDescription: false)
                }
                RainTilesRow(tiles: rainfall.pastTiles, style: .compact)
            } else {
                PlaceRowSkeleton()
            }
        }
        .padding(.vertical, 6)
        .animation(.easeInOut(duration: 0.25), value: rainfall == nil)
    }

    private func statusLine(
        condition: DirtCondition,
        rainfall: RainfallSummary,
        showDescription: Bool
    ) -> some View {
        HStack(spacing: 8) {
            ConditionBadge(condition: condition)
            if showDescription {
                Text(condition.shortDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            Spacer(minLength: 4)
            Label(rainfall.lastRainText, systemImage: "cloud.rain")
                .labelStyle(.titleAndIcon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .labelIconToTitleSpacing(3)
                .lineLimit(1)
                .fixedSize()
                .accessibilityLabel("Last rain \(rainfall.lastRainText)")
        }
    }
}

#Preview("Saved places") {
    NavigationStack {
        SavedPlacesListView(selectedDetent: .large)
            .navigationTitle("Saved places")
            .navigationBarTitleDisplayMode(.inline)
    }
    .previewEnvironment()
}

#Preview("Empty") {
    SavedPlacesListView(selectedDetent: .large)
        .previewEnvironment(store: SampleData.placeStore([]))
}
