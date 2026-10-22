import SwiftUI

struct SavedPlacesListView: View {
    @EnvironmentObject private var placeStore: PlaceStore
    var onSelectPlace: (Place) -> Void = { _ in }
    var selectedDetent: PresentationDetent

    @State private var rainfallData: [UUID: RainfallSummary] = [:]
    @State private var soilData: [UUID: SoilData] = [:]
    @State private var loadingPlaces: Set<UUID> = []
    @State private var errors: [UUID: String] = [:]
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
                    let trimmed = editingName.trimmingCharacters(
                        in: .whitespaces
                    )
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
            VStack(spacing: 0) {
                List {
                    ForEach(placeStore.places) { place in
                        Button {
                            onSelectPlace(place)
                        } label: {
                            PlaceRow(
                                place: place,
                                rainfall: rainfallData[place.id],
                                fetchedSoil: soilData[place.id],
                                isLoading: loadingPlaces.contains(place.id),
                                error: errors[place.id],
                                onRename: {
                                    editingName = place.name
                                    renamingPlace = place
                                }
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
                    rainfallData = [:]
                    soilData = [:]
                    errors = [:]
                    for place in placeStore.places {
                        let key = WeatherCache.key(
                            latitude: place.latitude,
                            longitude: place.longitude
                        )
                        await WeatherService.cache.invalidate(key: key)
                    }
                    await loadAllRainfall()
                }
                .task(id: placeStore.places.map(\.id)) {
                    await loadAllRainfall()
                }
            }
        }
    }

    private func loadAllRainfall() async {
        // Load anything without data, even if a previous (now cancelled) task
        // had it in flight: `.task(id:)` restarts whenever the list changes or
        // the view is rebuilt (e.g. folding/unfolding), and results are cached.
        let placesToLoad = placeStore.places.filter { rainfallData[$0.id] == nil }
        guard !placesToLoad.isEmpty else { return }
        for place in placesToLoad {
            loadingPlaces.insert(place.id)
            errors[place.id] = nil
        }

        await withTaskGroup(of: (UUID, Result<(RainfallSummary, SoilData), Error>).self) {
            group in
            for place in placesToLoad {
                group.addTask {
                    async let summaryTask = WeatherService.fetchRainfall(
                        latitude: place.latitude,
                        longitude: place.longitude
                    )
                    async let soilTask = SoilService.fetchSoilData(
                        latitude: place.latitude,
                        longitude: place.longitude
                    )
                    do {
                        let summary = try await summaryTask
                        let soil = await soilTask
                        return (place.id, .success((summary, soil)))
                    } catch {
                        return (place.id, .failure(error))
                    }
                }
            }

            for await (id, result) in group {
                switch result {
                case .success(let (summary, soil)):
                    rainfallData[id] = summary
                    soilData[id] = soil
                    errors[id] = nil
                    loadingPlaces.remove(id)
                case .failure(let error):
                    // A cancelled load is not an error; the restarted task
                    // picks the place up again.
                    if Task.isCancelled || (error as? URLError)?.code == .cancelled
                        || error is CancellationError
                    {
                        continue
                    }
                    errors[id] = Self.friendlyMessage(for: error)
                    loadingPlaces.remove(id)
                }
            }
        }
    }

    static func friendlyMessage(for error: Error, includeRetryHint: Bool = true) -> String {
        let hint = includeRetryHint ? " Pull down to try again." : ""
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return "You're offline." + hint
            case .timedOut:
                return "The weather service is slow right now." + hint
            default:
                break
            }
        }
        return "Couldn't load conditions." + hint
    }
}

// MARK: - Place Row

private struct PlaceRow: View {
    let place: Place
    let rainfall: RainfallSummary?
    let fetchedSoil: SoilData?
    let isLoading: Bool
    let error: String?
    var onRename: () -> Void

    private var effectiveSoil: SoilData? {
        place.soilOverride?.asSoilData ?? fetchedSoil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                POICategoryIcon(category: place.mapItem?.pointOfInterestCategory, size: 28)
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
