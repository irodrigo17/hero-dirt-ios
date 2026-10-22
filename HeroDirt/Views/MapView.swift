import MapKit
import SwiftUI

struct MapView: View {
    @EnvironmentObject private var placeStore: PlaceStore
    @EnvironmentObject private var mapItemCache: MapItemCache

    @State private var model = MapModel()
    @State private var gridService = RainfallGridService()
    @State private var showingAboutFromMap = false
    @State private var showingRainMapFromMap = false

    var body: some View {
        @Bindable var model = model
        GeometryReader { proxy in
            let split = MapModel.prefersSplit(for: proxy.size)
            // `map` keeps the same structural position in both layouts so the
            // MKMapView (and its camera) survives rotation.
            HStack(spacing: 0) {
                if model.isSplit {
                    sidebar
                        .verticalBarDisabled(true)
                        .frame(width: min(max(proxy.size.width * 0.4, 300), 420))
                        .background(Color(.systemGroupedBackground).ignoresSafeArea())
                        .transition(.move(edge: .leading))
                    Divider()
                        .ignoresSafeArea()
                }
                map
                    .overlay(alignment: .bottomTrailing) {
                        if model.isSplit {
                            floatingMapControls
                                .padding(.trailing, 16)
                                .padding(.bottom, 24)
                                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        }
                    }
            }
            .onAppear { model.applyLayout(split: split, places: placeStore.places, animated: false) }
            .onChange(of: split) { _, newValue in
                model.applyLayout(split: newValue, places: placeStore.places, animated: true)
            }
        }
        .onAppear {
            model.fitPlacesIfNeeded(placeStore.places)
        }
        .onChange(of: placeStore.places.isEmpty) { _, _ in
            // Saved places can arrive from iCloud after launch (e.g. after a
            // reinstall); frame them once they do.
            model.fitPlacesIfNeeded(placeStore.places)
        }
        .task(id: placeStore.places.map(\.id)) {
            mapItemCache.prefetch(places: placeStore.places)
        }
        .onChange(of: model.overlayVisible) { _, visible in
            Telemetry.signal(.rainMapToggled, ["visible": visible ? "true" : "false"])
            if visible, let region = model.visibleRegion {
                gridService.timeframe = model.overlayTimeframe
                gridService.updateRegion(region)
            }
        }
        .onChange(of: model.overlayTimeframe) { _, timeframe in
            if model.overlayVisible {
                gridService.timeframe = timeframe
                gridService.refetch()
            }
        }
        .sheet(
            isPresented: $model.isMainSheetPresented,
            onDismiss: {
                // The bottom sheet is permanent in the stacked layout.
                if !model.isSplit {
                    Task { @MainActor in model.isMainSheetPresented = true }
                }
            }
        ) {
            mainSheet
        }
    }

    // MARK: - Map

    private var map: some View {
        UIKitMapView(
            places: placeStore.places,
            newPinCoordinate: model.droppedPin?.coordinate,
            newPinTitle: model.droppedPin?.name,
            selectedSearchResult: model.searchResult,
            selectedAnnotation: model.annotationSelection(in: placeStore.places),
            overlayVisible: model.overlayVisible,
            overlayImage: gridService.overlay?.image,
            overlayBounds: gridService.overlay?.bounds,
            overlayOpacity: model.overlayOpacity,
            cameraCommand: Bindable(model).cameraCommand,
            onRegionChanged: { region in
                model.visibleRegion = region
                if model.overlayVisible {
                    gridService.updateRegion(region)
                }
            },
            onRegionWillChange: {
                if model.overlayVisible {
                    gridService.cancelUpdate()
                }
            },
            onLongPress: { coordinate in
                model.select(.droppedPin(coordinate, name: nil), places: placeStore.places, focus: false)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            },
            onAnnotationSelected: { annotation in
                switch annotation {
                case .place(let place):
                    model.select(.saved(place.id), places: placeStore.places)
                case .newPin, .searchResult:
                    // Already the selection; re-open details and re-center.
                    if let selection = model.selection {
                        model.select(selection, places: placeStore.places)
                    }
                }
            },
            onFeatureTapped: { item in
                model.select(.mapItem(item), places: placeStore.places)
            },
            onTap: {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil, from: nil, for: nil
                )
            },
            onUserLocationAvailable: { coordinate in
                model.userLocationAvailable(coordinate, hasPlaces: !placeStore.places.isEmpty)
            }
        )
        .ignoresSafeArea()
        .overlay(alignment: .top) {
            if model.overlayVisible, let message = gridService.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassEffect(.regular, in: Capsule())
                    .padding(.top, 8)
                    .padding(.horizontal)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { gridService.refetch() }
                    .accessibilityHint("Double tap to try again")
            }
        }
        .animation(.easeInOut(duration: 0.25), value: gridService.errorMessage)
    }

    /// Map actions for the split layout, in the bottom-trailing corner for
    /// easy thumb reach.
    private var floatingMapControls: some View {
        @Bindable var model = model
        return VStack(spacing: 12) {
            Button {
                showingAboutFromMap = true
            } label: {
                Image(systemName: "info")
                    .font(.body.weight(.semibold))
                    .frame(width: 48, height: 48)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("About Hero Dirt")

            VStack(spacing: 0) {
                Button {
                    showingRainMapFromMap = true
                } label: {
                    ZStack {
                        if gridService.isLoading {
                            ProgressView().controlSize(.small)
                        }
                        Image(systemName: model.overlayVisible ? "cloud.rain.fill" : "cloud.rain")
                            .opacity(gridService.isLoading ? 0 : 1)
                    }
                    .font(.title3)
                    .foregroundStyle(model.overlayVisible ? Color.blue : Color.primary)
                    .frame(width: 48, height: 48)
                }
                .accessibilityLabel("Rain map")
                .popover(isPresented: $showingRainMapFromMap, arrowEdge: .trailing) {
                    RainfallOverlaySheet(
                        isVisible: $model.overlayVisible,
                        timeframe: $model.overlayTimeframe,
                        opacity: $model.overlayOpacity,
                        isLoading: gridService.isLoading
                    )
                    .frame(idealWidth: 360, idealHeight: 520)
                    .presentationCompactAdaptation(.popover)
                }

                Divider().frame(width: 32)

                Button {
                    model.centerOnUser()
                } label: {
                    Image(systemName: "location.fill")
                        .font(.title3)
                        .foregroundStyle(Color.primary)
                        .frame(width: 48, height: 48)
                }
                .accessibilityLabel("Center map on your location")
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: Capsule())
        }
        .sheet(isPresented: $showingAboutFromMap) {
            AboutView()
        }
    }

    // MARK: - Sidebar (split layout)

    private var sidebar: some View {
        ZStack {
            sheetContent
            if let selection = model.selection {
                placeDetails(for: selection, onClose: model.closeDetails, isEmbedded: true)
                    .background(Color(.systemGroupedBackground).ignoresSafeArea())
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    .id(selection.identity)
                    .zIndex(1)
            }
        }
        .animation(.spring(duration: 0.35), value: model.selection != nil)
    }

    // MARK: - Sheets (stacked layout)

    private var sheetContent: some View {
        @Bindable var model = model
        return SheetView(
            onSelectPlace: { place in
                model.select(.saved(place.id), places: placeStore.places)
            },
            onSelectSearchResult: { item in
                Telemetry.signal(.searchResultSelected)
                model.select(.searchResult(item), places: placeStore.places)
            },
            onSearchFocusChanged: { focused in
                guard !model.isSplit else { return }
                model.sheetDetent = focused ? .large : .medium
            },
            visibleRegion: model.visibleRegion,
            selectedDetent: model.isSplit ? .large : model.sheetDetent,
            overlayVisible: $model.overlayVisible,
            overlayTimeframe: $model.overlayTimeframe,
            overlayOpacity: $model.overlayOpacity,
            isOverlayLoading: gridService.isLoading,
            onCenterLocation: model.centerOnUser,
            showsMapActions: !model.isSplit
        )
    }

    private var mainSheet: some View {
        @Bindable var model = model
        return sheetContent
            .presentationDetents(
                [MapModel.collapsedDetent, .medium, .large],
                selection: $model.sheetDetent
            )
            .presentationBackgroundInteraction(.enabled)
            .interactiveDismissDisabled(true)
            .sheet(
                isPresented: $model.isDetailsSheetPresented,
                onDismiss: {
                    // Rotating into the split layout dismisses the sheets but
                    // keeps the selection, which moves into the sidebar.
                    guard !model.isSplit else { return }
                    model.closeDetails()
                }
            ) {
                if let selection = model.selection {
                    placeDetails(for: selection, onClose: { model.isDetailsSheetPresented = false })
                        .presentationBackgroundInteraction(.enabled)
                }
            }
    }

    private func placeDetails(
        for selection: Selection,
        onClose: @escaping () -> Void,
        isEmbedded: Bool = false
    ) -> some View {
        let isDroppedPin = model.droppedPin != nil
        return PlaceDetailsView(
            coordinate: selection.coordinate(in: placeStore.places) ?? CLLocationCoordinate2D(),
            placeID: selection.savedPlaceID,
            mapItem: selection.mapItem,
            onClose: onClose,
            onNameResolved: isDroppedPin ? { model.droppedPinNamed($0) } : nil,
            onSaved: isDroppedPin ? { model.didSave($0) } : nil,
            onUnsaved: { model.didUnsave($0) },
            isEmbedded: isEmbedded
        )
        .environmentObject(placeStore)
        .environmentObject(mapItemCache)
    }
}
