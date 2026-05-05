import SwiftUI
import MapKit

struct LocationRainfallSheet: View {
    @EnvironmentObject private var placeStore: PlaceStore
    @Environment(\.dismiss) private var dismiss

    let coordinate: CLLocationCoordinate2D
    var placeID: UUID? = nil
    var mapItem: MKMapItem? = nil

    @State private var placeName = "Loading..."
    @State private var rainfallSummary: RainfallSummary?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingRenameAlert = false
    @State private var editingName = ""

    private var savedPlace: Place? {
        if let placeID, let place = placeStore.places.first(where: { $0.id == placeID }) {
            return place
        }
        return placeStore.placeNear(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    private var subtitle: String? {
        mapItem?.pointOfInterestCategory?.displayName ?? mapItem?.addressRepresentations?.cityWithContext
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
                        RainfallCardView(summary: summary)
                    }

                    Text(String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude))
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                    Button { dismiss() } label: {
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
        .task {
            await loadData()
        }
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
        if let saved = savedPlace {
            placeName = saved.name
        } else if let name = mapItem?.name {
            placeName = name
        } else {
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            if let request = MKReverseGeocodingRequest(location: location) {
                do {
                    let mapItems = try await request.mapItems
                    if let item = mapItems.first,
                       let cityContext = item.addressRepresentations?.cityWithContext {
                        placeName = cityContext
                    } else {
                        placeName = formatCoordinate()
                    }
                } catch {
                    placeName = formatCoordinate()
                }
            } else {
                placeName = formatCoordinate()
            }
        }

        do {
            rainfallSummary = try await WeatherService.fetchRainfall(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func formatCoordinate() -> String {
        String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude)
    }

    private func toggleSaved() {
        if let existing = savedPlace {
            placeStore.removePlace(existing)
        } else {
            placeStore.addPlace(
                Place(name: placeName, latitude: coordinate.latitude, longitude: coordinate.longitude)
            )
        }
    }

    private func openInMaps() {
        if let mapItem {
            mapItem.openInMaps()
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

