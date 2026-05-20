import MapKit
import SwiftUI

struct PlaceDetailsView: View {
    @EnvironmentObject private var placeStore: PlaceStore
    @EnvironmentObject private var mapItemCache: MapItemCache
    @Environment(\.dismiss) private var dismiss

    let coordinate: CLLocationCoordinate2D
    var placeID: UUID? = nil
    var mapItem: MKMapItem? = nil
    var onClose: (() -> Void)? = nil
    var onNameResolved: ((String) -> Void)? = nil
    var onSaved: (() -> Void)? = nil

    @State private var placeName = "Loading..."
    @State private var rainfallSummary: RainfallSummary?
    @State private var rainForecast: RainForecast?
    @State private var soilData: SoilData?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingRenameAlert = false
    @State private var showSoilOverrideSheet = false
    @State private var editingName = ""
    private var savedPlace: Place? {
        if let placeID,
            let place = placeStore.places.first(where: { $0.id == placeID })
        {
            return place
        }
        return placeStore.placeNear(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
    }

    private var effectiveMapItem: MKMapItem? { mapItem ?? savedPlace?.mapItem }

    private var subtitle: String? {
        effectiveMapItem?.pointOfInterestCategory?.displayName
            ?? effectiveMapItem?.addressRepresentations?.cityWithContext
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    actionBar

                    if isLoading {
                        ProgressView("Loading rainfall data...")
                            .padding(.top, 40)
                    } else if let errorMessage {
                        ContentUnavailableView(
                            "Unable to load rainfall data",
                            systemImage: "exclamationmark.triangle",
                            description: Text(errorMessage)
                        )
                    } else if let summary = rainfallSummary {
                        DirtConditionCardView(
                            result: summary.dirtConditionResult(soil: soilData),
                            onCustomize: savedPlace != nil
                                ? { showSoilOverrideSheet = true } : nil,
                            isOverridden: savedPlace?.soilOverride != nil
                        )
                        RainfallCardView(summary: summary)
                        if let forecast = rainForecast {
                            RainForecastCardView(forecast: forecast)
                        }
                    }
                }
                .padding()
            }
            .refreshable {
                await refreshData()
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle(
                Text(placeName)
            )
            .navigationSubtitle(
                Text(subtitle ?? "")
            )
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if let onClose { onClose() } else { dismiss() }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.primary)
                    }
                    .accessibilityLabel("Close")
                }
            }
            .alert("Rename", isPresented: $showingRenameAlert) {
                TextField("Name", text: $editingName)
                Button("Save") {
                    let trimmed = editingName.trimmingCharacters(
                        in: .whitespaces
                    )
                    guard !trimmed.isEmpty else { return }
                    placeName = trimmed
                    if let existing = savedPlace {
                        placeStore.renamePlace(existing, to: trimmed)
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .presentationDetents([.medium, .large])
        .task(id: loadKey) {
            await loadData()
        }
        .sheet(isPresented: $showSoilOverrideSheet) {
            if let place = savedPlace {
                SoilOverrideSheet(currentOverride: place.soilOverride) { newOverride in
                    placeStore.updateSoilOverride(newOverride, for: place)
                    applySoilOverride(newOverride)
                    showSoilOverrideSheet = false
                }
            }
        }
    }

    private struct LoadKey: Hashable {
        let latitude: Double
        let longitude: Double
        let placeID: UUID?
    }

    private var loadKey: LoadKey {
        LoadKey(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            placeID: placeID
        )
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 12) {
            SheetActionButton(
                icon: savedPlace != nil ? "star.fill" : "star",
                label: savedPlace != nil ? "Saved" : "Save",
                isPrimary: true,
                isDisabled: isLoading,
                action: toggleSaved
            )
            SheetActionButton(
                icon: "map",
                label: "Maps",
                isPrimary: false,
                isDisabled: isLoading,
                action: openInMaps
            )
            SheetActionButton(
                icon: "pencil",
                label: "Rename",
                isPrimary: false,
                isDisabled: isLoading
            ) {
                editingName = placeName
                showingRenameAlert = true
            }
        }
    }

    // MARK: - Data Loading

    private func loadData() async {
        placeName = "Loading..."
        rainfallSummary = nil
        rainForecast = nil
        soilData = nil
        isLoading = true
        errorMessage = nil

        if let saved = savedPlace { await mapItemCache.fetch(for: saved) }
        guard !Task.isCancelled else { return }

        if let saved = savedPlace {
            placeName = saved.name
        } else if let name = mapItem?.name {
            placeName = name
        } else {
            let location = CLLocation(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
            if let request = MKReverseGeocodingRequest(location: location) {
                do {
                    let mapItems = try await request.mapItems
                    guard !Task.isCancelled else { return }
                    if let item = mapItems.first,
                        let cityContext = item.addressRepresentations?
                            .cityWithContext
                    {
                        placeName = cityContext
                    } else {
                        placeName = formatCoordinate()
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                    placeName = formatCoordinate()
                }
            } else {
                placeName = formatCoordinate()
            }
        }

        onNameResolved?(placeName)
        guard !Task.isCancelled else { return }
        await fetchWeatherAndSoil()
        isLoading = false
    }

    private func refreshData() async {
        let key = WeatherCache.key(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        await WeatherService.cache.invalidate(key: key)
        await fetchWeatherAndSoil()
    }

    private func fetchWeatherAndSoil() async {
        async let rainfallTask = WeatherService.fetchRainfall(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        async let forecastTask = WeatherService.fetchRainForecast(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        async let soilTask = SoilService.resolveOrFetch(
            override: savedPlace?.soilOverride,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )

        do {
            rainfallSummary = try await rainfallTask
            errorMessage = nil
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }

        guard !Task.isCancelled else { return }
        soilData = await soilTask
        rainForecast = try? await forecastTask
    }

    private func applySoilOverride(_ override: SoilOverride?) {
        if let override {
            soilData = override.asSoilData
        } else {
            Task {
                soilData = await SoilService.fetchSoilData(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude
                )
            }
        }
    }

    private func formatCoordinate() -> String {
        String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude)
    }

    private func toggleSaved() {
        if let existing = savedPlace {
            placeStore.removePlace(existing)
        } else {
            placeStore.addPlace(
                Place(
                    name: placeName,
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                    mapItemId: mapItem?.identifier
                )
            )
            onSaved?()
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func openInMaps() {
        if let item = effectiveMapItem {
            item.openInMaps()
        } else {
            let item = MKMapItem(
                location: CLLocation(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude
                ),
                address: nil
            )
            item.name = placeName
            item.openInMaps()
        }
    }
}

// MARK: - Action Button

private struct SheetActionButton: View {
    let icon: String
    let label: String
    let isPrimary: Bool
    let isDisabled: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                Text(label)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundStyle(isPrimary ? .white : .blue)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                isPrimary ? Color.blue : Color.blue.opacity(0.1),
                in: RoundedRectangle(cornerRadius: .cornerLarge)
            )
        }
        .disabled(isDisabled)
    }
}
