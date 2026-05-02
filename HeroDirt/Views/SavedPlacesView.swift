import SwiftUI
import MapKit

struct SavedPlacesView: View {
    @EnvironmentObject private var placeStore: PlaceStore

    @State private var rainfallData: [UUID: RainfallSummary] = [:]
    @State private var loadingPlaces: Set<UUID> = []
    @State private var errors: [UUID: String] = [:]
    @State private var renamingPlace: Place?
    @State private var editingName = ""

    var body: some View {
        NavigationStack {
            Group {
                if placeStore.places.isEmpty {
                    ContentUnavailableView(
                        "No Saved Places",
                        systemImage: "star",
                        description: Text("Tap anywhere on the map to check rainfall, then tap the star to save it here.")
                    )
                } else {
                    List {
                        ForEach(placeStore.places) { place in
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
                            .swipeActions(edge: .leading) {
                                Button {
                                    openInMaps(place)
                                } label: {
                                    Label("Maps", systemImage: "map")
                                }
                                .tint(.blue)
                            }
                        }
                        .onDelete { offsets in
                            placeStore.removePlaces(at: offsets)
                        }
                    }
                }
            }
            .navigationTitle("Saved Places")
            .refreshable {
                await loadAllRainfall()
            }
            .task {
                await loadAllRainfall()
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
    }

    private func openInMaps(_ place: Place) {
        let mapItem = MKMapItem(location: CLLocation(latitude: place.latitude, longitude: place.longitude), address: nil)
        mapItem.name = place.name
        mapItem.openInMaps()
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
                Button(action: onRename) {
                    Image(systemName: "pencil")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
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
