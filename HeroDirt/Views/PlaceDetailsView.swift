import MapKit
import SwiftUI

struct PlaceDetailsView: View {
    @Environment(PlaceStore.self) private var placeStore
    @Environment(MapItemCache.self) private var mapItemCache
    @Environment(\.weather) private var weather
    @Environment(\.soil) private var soil
    @Environment(\.rainUnit) private var rainUnit
    @Environment(\.drivingTime) private var drivingTime
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss

    let coordinate: CLLocationCoordinate2D
    var placeID: UUID? = nil
    var mapItem: MKMapItem? = nil
    var onClose: (() -> Void)? = nil
    var onNameResolved: ((String) -> Void)? = nil
    var onSaved: ((Place) -> Void)? = nil
    var onUnsaved: ((Place) -> Void)? = nil
    var style: Style = .sheet

    enum Style {
        /// Presented as a sheet: own navigation stack, close button.
        case sheet
        /// Inside the map's split-layout sidebar: leading back button.
        case sidebar
        /// Pushed onto an existing navigation stack (trails list): system back.
        case pushed
    }

    @State private var sharePayload: TrailSharePayload?
    @State private var shareError = false
    @State private var websiteURL: URL?
    @State private var websiteTask: Task<Void, Never>?
    @State private var drivingSeconds: TimeInterval?
    @State private var drivingTimeTask: Task<Void, Never>?
    @State private var drivingTimeKey: LoadKey?
    @State private var placeName = "Loading…"
    @State private var rainfallSummary: RainfallSummary?
    @State private var rainForecast: RainForecast?
    @State private var soilData: SoilData?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingRenameAlert = false
    @State private var showingDeleteConfirmation = false
    @State private var showSoilOverrideSheet = false
    @State private var editingName = ""
    /// The load runs in its own task rather than the view's `.task`, which
    /// SwiftUI can cancel while the view is being pushed or rebuilt (that
    /// left the screen stuck loading or blank).
    @State private var loadTask: Task<Void, Never>?
    @State private var loadedKey: LoadKey?
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

    private var effectiveMapItem: MKMapItem? {
        mapItem ?? savedPlace.flatMap { mapItemCache.items[$0.id] }
    }

    var body: some View {
        Group {
            if style == .pushed {
                page
            } else {
                NavigationStack { page }
            }
        }
        .presentationDetents([.medium, .large])
        .task(id: loadKey) {
            startLoading()
        }
        .task(id: DrivingTimeLoadKey(place: loadKey, isActive: scenePhase == .active)) {
            guard scenePhase == .active else { return }
            startDrivingTimeLoad()
        }
        .onChange(of: effectiveMapItem.map(ObjectIdentifier.init), initial: true) { _, _ in
            prepareWebsite(for: effectiveMapItem)
        }
        .sheet(item: $sharePayload) { payload in
            TrailShareSheet(payload: payload)
                .presentationDetents([.medium, .large])
        }
        .alert("Couldn't create share image", isPresented: $shareError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please try sharing this trail again.")
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

    private var page: some View {
            ScrollView {
                VStack(spacing: 20) {
                    actionBar

                    if isLoading {
                        PlaceDetailsSkeleton()
                            .transition(.opacity)
                    } else if let errorMessage {
                        ContentUnavailableView {
                            Label("Couldn't load trail conditions", systemImage: "exclamationmark.triangle")
                        } description: {
                            Text(errorMessage)
                        } actions: {
                            Button("Try Again") {
                                Task { await reload() }
                            }
                            .buttonStyle(.bordered)
                        }
                    } else if rainfallSummary == nil {
                        ContentUnavailableView {
                            Label("No conditions yet", systemImage: "cloud.rain")
                        } actions: {
                            Button("Load Conditions") {
                                Task { await reload() }
                            }
                            .buttonStyle(.bordered)
                        }
                    } else if let summary = rainfallSummary {
                        let result = summary.dirtConditionResult(soil: soilData)
                        DirtConditionCardView(
                            result: result,
                            onCustomize: savedPlace != nil
                                ? { showSoilOverrideSheet = true } : nil,
                            isOverridden: savedPlace?.soilOverride != nil
                        )
                        let strip = summary.strip(soil: soilData)
                        if strip.count > 1 {
                            OutlookCardView(current: result.condition, days: strip)
                        }
                        let timeline = summary.timeline(soil: soilData)
                        if !timeline.isEmpty {
                            ConditionTrendView(timeline: timeline)
                        }
                        RainfallCardView(summary: summary)
                        if let forecast = rainForecast {
                            RainForecastCardView(forecast: forecast)
                        }
                    }
                }
                .padding()
                .animation(.easeInOut(duration: 0.25), value: isLoading)
            }
            .refreshable {
                async let estimate: () = refreshDrivingTime()
                await refreshData()
                await estimate
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle(
                Text(placeName)
            )
            .toolbar {
                switch style {
                case .pushed:
                    ToolbarItem(placement: .topBarTrailing) { EmptyView() }
                case .sidebar:
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            if let onClose { onClose() } else { dismiss() }
                        } label: {
                            Image(systemName: "chevron.backward")
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                        }
                        .accessibilityLabel("Back to saved places")
                    }
                case .sheet:
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
            }
            .confirmationDialog("Delete this trail?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete Trail", role: .destructive) {
                    guard let existing = savedPlace else { return }
                    placeStore.removePlace(existing)
                    onUnsaved?(existing)
                    Telemetry.signal(.placeRemoved)
                    if let onClose { onClose() } else { dismiss() }
                }
            } message: {
                Text("This removes \(placeName) from your saved trails on all your devices.")
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

    private struct DrivingTimeLoadKey: Hashable {
        let place: LoadKey
        let isActive: Bool
    }

    private func prepareWebsite(for item: MKMapItem?) {
        websiteTask?.cancel()
        websiteURL = nil
        guard let item else { return }
        // Keep preparation independent of SwiftUI task cancellation during a push.
        // Menu construction only reads the prepared URL, never lazy MapKit data.
        websiteTask = Task {
            let url = await PlaceWebsite.url(for: item)
            guard !Task.isCancelled else { return }
            websiteURL = url
            websiteTask = nil
        }
    }

    private func refreshDrivingTime() async {
        await startDrivingTimeLoad(forceRefresh: true).value
    }

    /// Keep the request alive across navigation updates and the inactive phase
    /// caused by a location permission prompt, just like the conditions load.
    @discardableResult
    private func startDrivingTimeLoad(forceRefresh: Bool = false) -> Task<Void, Never> {
        if !forceRefresh, drivingTimeKey == loadKey {
            if let drivingTimeTask { return drivingTimeTask }
            if drivingSeconds != nil { return Task {} }
        }
        drivingTimeTask?.cancel()
        drivingTimeKey = loadKey
        drivingSeconds = nil
        let destination = coordinate
        let task = Task {
            let seconds = await drivingTime.travelTime(to: destination)
            guard !Task.isCancelled else { return }
            drivingSeconds = seconds
            drivingTimeTask = nil
        }
        drivingTimeTask = task
        return task
    }

    // Saving changes the place ID, but not the location or its conditions.
    // Keep that transition from restarting the load and flashing skeletons.
    private struct LoadKey: Hashable {
        let latitude: Double
        let longitude: Double
    }

    private var loadKey: LoadKey {
        LoadKey(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 12) {
            if savedPlace == nil {
                SheetActionButton(
                    icon: "star",
                    label: "Save",
                    isPrimary: true,
                    isDisabled: isLoading,
                    action: savePlace
                )
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
            SheetActionButton(
                icon: "car.fill",
                label: DrivingTimeLabel.text(for: drivingSeconds),
                isPrimary: false,
                isDisabled: isLoading,
                action: openDirections
            )
            .accessibilityIdentifier("Driving Directions")
            .accessibilityLabel(drivingSeconds == nil ? "Directions" : "Driving time: \(DrivingTimeLabel.text(for: drivingSeconds))")
            .accessibilityHint("Opens driving directions in Apple Maps")
            moreMenu
        }
        .animation(.smooth(duration: 0.3), value: savedPlace != nil)
    }

    private var moreMenu: some View {
        Menu {
            Button(action: shareTrail) {
                Label("Share Trail", systemImage: "square.and.arrow.up")
            }
            .disabled(rainfallSummary == nil || isLoading)
            Button(action: openInMaps) {
                Label("Open in Maps", systemImage: "map")
            }
            if let websiteURL {
                Link(destination: websiteURL) {
                    Label("Website", systemImage: "safari")
                }
            }
            if savedPlace != nil {
                Button {
                    editingName = placeName
                    showingRenameAlert = true
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                Button {
                    showSoilOverrideSheet = true
                } label: {
                    Label("Trail Settings", systemImage: "slider.horizontal.3")
                }
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete Trail", systemImage: "trash")
                }
            }
        } label: {
            SheetActionLabel(icon: "ellipsis", label: "More", isPrimary: false)
        }
        .accessibilityIdentifier("Trail Options")
    }

    // MARK: - Data Loading

    private func startLoading() {
        if loadedKey == loadKey, loadTask != nil || rainfallSummary != nil || errorMessage != nil {
            return
        }
        loadedKey = loadKey
        loadTask?.cancel()
        loadTask = Task {
            await loadData()
            loadTask = nil
        }
    }

    private func loadData() async {
        placeName = "Loading…"
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
        // A cancelled load (the view disappeared, or a newer load started)
        // must not end the loading state with no data: that left a blank
        // screen. The load that is still running finishes it.
        guard !Task.isCancelled else { return }
        isLoading = false
    }

    private func reload() async {
        isLoading = true
        errorMessage = nil
        await refreshData()
        isLoading = false
    }

    private func refreshData() async {
        await weather.invalidate(latitude: coordinate.latitude, longitude: coordinate.longitude)
        await fetchWeatherAndSoil()
    }

    private func fetchWeatherAndSoil() async {
        // Soil can be slow (throttled SoilGrids); don't hold the screen for
        // it. Conditions show with estimated loam and refine when it lands.
        Task { await loadSoil() }

        async let rainfallTask = weather.rainfall(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        async let forecastTask = weather.forecast(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )

        do {
            rainfallSummary = try await rainfallTask
            errorMessage = nil
            if let summary = rainfallSummary {
                Telemetry.signal(.conditionsViewed, ["condition": summary.dirtCondition().label])
            }
        } catch {
            guard !Task.isCancelled, !PlaceConditionsModel.isCancellation(error) else { return }
            errorMessage = PlaceConditionsModel.friendlyMessage(for: error, includeRetryHint: false)
        }

        guard !Task.isCancelled else { return }
        rainForecast = try? await forecastTask
    }

    private func loadSoil() async {
        let place = savedPlace
        let resolved = await soil.resolve(
            override: place?.soilOverride,
            stored: place?.soil,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        soilData = resolved
        if let place, place.soil == nil, place.soilOverride == nil, !resolved.isEstimated {
            placeStore.updateSoil(resolved, for: place.id)
        }
    }

    private func applySoilOverride(_ override: SoilOverride?) {
        if let override {
            soilData = override.asSoilData
        } else {
            Task { await loadSoil() }
        }
    }

    private func formatCoordinate() -> String {
        String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude)
    }

    private func savePlace() {
        guard savedPlace == nil else { return }
        let newPlace = Place(
            name: placeName,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            mapItemId: mapItem?.identifier
        )
        placeStore.addPlace(newPlace)
        onSaved?(newPlace)
        Telemetry.signal(.placeSaved)
        // Keep the soil with the place so it never needs another lookup.
        if let soilData, !soilData.isEstimated {
            placeStore.updateSoil(soilData, for: newPlace.id)
        } else {
            Task {
                if let result = await soil.soil(
                    latitude: newPlace.latitude, longitude: newPlace.longitude
                ) {
                    placeStore.updateSoil(result, for: newPlace.id)
                }
            }
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func shareTrail() {
        guard let summary = rainfallSummary else { return }
        let renderer = ImageRenderer(content: TrailSharingCard(
            name: placeName, summary: summary, soil: soilData, sharedAt: .now
        ).environment(\.rainUnit, rainUnit))
        renderer.scale = 3
        guard let image = renderer.uiImage else { shareError = true; return }
        let trail = SharedTrail(
            name: placeName, coordinate: coordinate,
            mapItemID: savedPlace?.mapItemIdString ?? effectiveMapItem?.identifier?.rawValue
        )
        let condition = summary.dirtCondition(soil: soilData).label
        sharePayload = TrailSharePayload(
            image: image, text: trail.message(condition: condition),
            url: trail.appURL, title: "\(placeName) — \(condition)"
        )
    }

    private func openDirections() {
        Telemetry.signal(.directionsOpened)
        openMapItem(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }

    private func openInMaps() {
        openMapItem(launchOptions: nil)
    }

    private func openMapItem(launchOptions: [String: Any]?) {
        if let item = effectiveMapItem {
            item.openInMaps(launchOptions: launchOptions)
        } else {
            let item = MKMapItem(
                location: CLLocation(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude
                ),
                address: nil
            )
            item.name = placeName
            item.openInMaps(launchOptions: launchOptions)
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
            SheetActionLabel(icon: icon, label: label, isPrimary: isPrimary)
        }
        .disabled(isDisabled)
    }
}

private struct SheetActionLabel: View {
    let icon: String
    let label: String
    let isPrimary: Bool

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .frame(height: 24)
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
        }
        .foregroundStyle(isPrimary ? .white : .blue)
        .frame(maxWidth: .infinity, minHeight: 44)
        .padding(.vertical, 8)
        .background(
            isPrimary ? Color.blue : Color.blue.opacity(0.1),
            in: RoundedRectangle(cornerRadius: .cornerLarge)
        )
    }
}

#Preview("Saved place") {
    PlaceDetailsView(
        coordinate: SampleData.places[0].coordinate,
        placeID: SampleData.places[0].id
    )
    .previewEnvironment()
}

#Preview("Error") {
    PlaceDetailsView(coordinate: SampleData.places[1].coordinate)
        .previewEnvironment()
        .environment(\.weather, FakeWeatherProvider(failure: URLError(.notConnectedToInternet)))
}
