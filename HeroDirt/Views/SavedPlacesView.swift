import SwiftUI
import MapKit

struct SavedPlacesView: View {
    @EnvironmentObject private var placeStore: PlaceStore
    var onSelectPlace: (Place) -> Void = { _ in }
    var onSelectSearchResult: (MKMapItem) -> Void = { _ in }
    var onSearchFocusChanged: (Bool) -> Void = { _ in }
    var visibleRegion: MKCoordinateRegion? = nil

    @State private var rainfallData: [UUID: RainfallSummary] = [:]
    @State private var loadingPlaces: Set<UUID> = []
    @State private var errors: [UUID: String] = [:]
    @State private var renamingPlace: Place?
    @State private var editingName = ""

    @State private var searchText = ""
    @State private var isSearchFocused = false
    @State private var searchResults: [MKMapItem] = []
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            SearchBar(
                text: $searchText,
                isFocused: $isSearchFocused,
                onSearchTapped: {
                    searchTask?.cancel()
                    guard !searchText.isEmpty else { return }
                    searchTask = Task { await runSearch(query: searchText) }
                }
            )
            .padding(8)
            
            if isSearchFocused {
                searchResultsContent
            } else {
                savedPlacesContent
            }
        }
        .task {
            await loadAllRainfall()
        }
        .onChange(of: isSearchFocused) { _, focused in
            onSearchFocusChanged(focused)
            if !focused {
                searchText = ""
                searchResults = []
                searchTask?.cancel()
            }
        }
        .onChange(of: searchText) { _, newValue in
            searchTask?.cancel()
            guard !newValue.isEmpty else {
                searchResults = []
                return
            }
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                await runSearch(query: newValue)
            }
        }
        .alert("Rename", isPresented: Binding(
            get: { renamingPlace != nil },
            set: { if !$0 { renamingPlace = nil } }
        )) {
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
    private var searchResultsContent: some View {
        if searchResults.isEmpty {
            Spacer()
        } else {
            List {
                ForEach(searchResults, id: \.self) { item in
                    Button {
                        isSearchFocused = false
                        onSelectSearchResult(item)
                    } label: {
                        HStack(spacing: 10) {
                            POICategoryIcon(category: item.pointOfInterestCategory)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name ?? "Unknown")
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                if let subtitle = item.placemark.title, subtitle != item.name {
                                    Text(subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private var savedPlacesContent: some View {
        if placeStore.places.isEmpty {
            ContentUnavailableView(
                "No saved places",
                systemImage: "star",
                description: Text("Tap anywhere on the map to check rainfall, then tap the star to save it here.")
            )
        } else {
            List {
                Section(header: Text("Saved places")) {
                    ForEach(placeStore.places) { place in
                        Button {
                            onSelectPlace(place)
                        } label: {
                            PlaceRow(
                                place: place,
                                rainfall: rainfallData[place.id],
                                isLoading: loadingPlaces.contains(place.id),
                                error: errors[place.id],
                                onRename: {
                                    editingName = place.name
                                    renamingPlace = place
                                }
                            )
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .leading) {
                            Button {
                                editingName = place.name
                                renamingPlace = place
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                    .onDelete { offsets in
                        placeStore.removePlaces(at: offsets)
                    }
                }
            }
            .listStyle(.plain)
            .refreshable {
                await loadAllRainfall()
            }
        }
    }

    private func runSearch(query: String) async {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        if let region = visibleRegion {
            request.region = region
        }
        request.resultTypes = [.pointOfInterest, .physicalFeature]
        do {
            let response = try await MKLocalSearch(request: request).start()
            searchResults = response.mapItems
        } catch {
            searchResults = []
        }
    }

    private func loadAllRainfall() async {
        let placesToLoad = placeStore.places
        for place in placesToLoad {
            loadingPlaces.insert(place.id)
        }

        await withTaskGroup(of: (UUID, Result<RainfallSummary, Error>).self) { group in
            for place in placesToLoad {
                group.addTask {
                    do {
                        let summary = try await WeatherService.fetchRainfall(
                            latitude: place.latitude,
                            longitude: place.longitude
                        )
                        return (place.id, .success(summary))
                    } catch {
                        return (place.id, .failure(error))
                    }
                }
            }

            for await (id, result) in group {
                loadingPlaces.remove(id)
                switch result {
                case .success(let summary):
                    rainfallData[id] = summary
                    errors[id] = nil
                case .failure(let error):
                    errors[id] = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Place Row

private struct PlaceRow: View {
    let place: Place
    let rainfall: RainfallSummary?
    let isLoading: Bool
    let error: String?
    var onRename: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(place.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if let rainfall {
                    lastRainBadge(rainfall)
                }
            }

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 4)
            } else if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if let rainfall {
                HStack(spacing: 8) {
                    compactTile("1d", value: rainfall.last1Day)
                    compactTile("2d", value: rainfall.last2Days)
                    compactTile("3d", value: rainfall.last3Days)
                    compactTile("7d", value: rainfall.last7Days)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func lastRainBadge(_ rainfall: RainfallSummary) -> some View {
        if let days = rainfall.daysSinceLastRain {
            switch days {
            case 0:
                Label("Today", systemImage: "cloud.rain")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case 1:
                Label("1d ago", systemImage: "cloud.rain")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            default:
                Label("\(days)d ago", systemImage: "cloud.rain")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Label("30d+", systemImage: "sun.max")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func compactTile(_ label: String, value: Double) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(formatMM(value))
                .font(.callout)
                .fontWeight(.semibold)
                .foregroundStyle(value > 0 ? .blue : .secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(value > 0 ? Color.blue.opacity(0.08) : Color.gray.opacity(0.05),
                     in: RoundedRectangle(cornerRadius: 6))
    }

    private func formatMM(_ value: Double) -> String {
        value < 10 ? String(format: "%.1f", value) : String(format: "%.0f", value)
    }
}
