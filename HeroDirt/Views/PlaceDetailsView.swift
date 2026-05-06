import SwiftUI
import MapKit

struct PlaceDetailsView: View {
    @EnvironmentObject private var placeStore: PlaceStore
    @Environment(\.dismiss) private var dismiss

    let coordinate: CLLocationCoordinate2D
    var placeID: UUID? = nil
    var mapItem: MKMapItem? = nil
    var onClose: (() -> Void)? = nil

    @State private var placeName = "Loading..."
    @State private var rainfallSummary: RainfallSummary?
    @State private var rainForecast: RainForecast?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingRenameAlert = false
    @State private var editingName = ""
    @State private var resolvedMapItem: MKMapItem?

    private var savedPlace: Place? {
        if let placeID, let place = placeStore.places.first(where: { $0.id == placeID }) {
            return place
        }
        return placeStore.placeNear(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    private var effectiveMapItem: MKMapItem? { mapItem ?? resolvedMapItem }

    private var subtitle: String? {
        effectiveMapItem?.pointOfInterestCategory?.displayName ?? effectiveMapItem?.addressRepresentations?.cityWithContext
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
                            "Error",
                            systemImage: "exclamationmark.triangle",
                            description: Text(errorMessage)
                        )
                    } else if let summary = rainfallSummary {
                        DirtConditionCardView(condition: summary.dirtCondition)
                        RainfallCardView(summary: summary)
                        if let forecast = rainForecast {
                            RainForecastCardView(forecast: forecast)
                        }
                    }
                }
                .padding()
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
                }
            }
            .alert("Rename", isPresented: $showingRenameAlert) {
                TextField("Name", text: $editingName)
                Button("Save") {
                    let trimmed = editingName.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    placeName = trimmed
                    if let existing = savedPlace {
                        placeStore.renamePlace(existing, to: trimmed)
                    }
                }
                Button("Cancel", role: .cancel) { }
            }
        }
        .presentationDetents([.medium, .large])
        .task(id: loadKey) {
            await loadData()
        }
    }

    private var loadKey: String {
        "\(coordinate.latitude),\(coordinate.longitude),\(placeID?.uuidString ?? "")"
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
    
    func fetchMapItem(from identifier: MKMapItem.Identifier?) async -> MKMapItem? {
        guard let identifier else { return nil }
        let request = MKMapItemRequest(mapItemIdentifier: identifier)
        
        do {
            let mapItem = try await request.mapItem
            return mapItem
        } catch {
            return nil
        }
    }

    private func loadData() async {
        placeName = "Loading..."
        rainfallSummary = nil
        rainForecast = nil
        resolvedMapItem = nil
        isLoading = true
        errorMessage = nil

        resolvedMapItem = await fetchMapItem(from: savedPlace?.mapItemId)

        if let saved = savedPlace {
            placeName = saved.name
        } else if let name = mapItem?.name {
            placeName = name
        } else {
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            if let request = MKReverseGeocodingRequest(location: location) {
                do {
                    let mapItems = try await request.mapItems
                    guard !Task.isCancelled else { return }
                    if let item = mapItems.first,
                       let cityContext = item.addressRepresentations?.cityWithContext {
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

        async let rainfallTask = WeatherService.fetchRainfall(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        async let forecastTask = WeatherService.fetchRainForecast(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )

        do {
            rainfallSummary = try await rainfallTask
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }

        isLoading = false

        rainForecast = try? await forecastTask
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
        }
    }

    private func openInMaps() {
        if let item = effectiveMapItem {
            item.openInMaps()
        } else {
            let item = MKMapItem(location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude), address: nil)
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
            .background(isPrimary ? Color.blue : Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
        }
        .disabled(isDisabled)
    }
}

