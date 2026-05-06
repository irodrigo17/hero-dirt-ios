# Saved Places → Map Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tapping a PlaceRow in SavedPlacesView switches to the Map tab, selects that place's pin, and opens the bottom sheet with the camera flying to the place.

**Architecture:** Navigation state (`selectedTab`, `pendingPlace`) lives in `ContentView`, which owns the `TabView`. `MapExploreView` accepts a `@Binding var pendingPlace: Place?` and acts on it via `onChange`. `SavedPlacesView` accepts an `onSelectPlace: (Place) -> Void` callback. No new types; no changes to `PlaceStore`.

**Tech Stack:** SwiftUI, MapKit, Swift 5.9+

---

## Files

- Modify: `HeroDirt/ContentView.swift`
- Modify: `HeroDirt/Views/MapExploreView.swift`
- Modify: `HeroDirt/Views/SavedPlacesView.swift`

---

### Task 1: Bind TabView selection in ContentView

**Files:**
- Modify: `HeroDirt/ContentView.swift`

- [ ] **Step 1: Add selectedTab state and bind TabView**

Replace the entire contents of `HeroDirt/ContentView.swift` with:

```swift
import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            MapExploreView()
                .tabItem {
                    Label("Map", systemImage: "map")
                }
                .tag(0)
            SavedPlacesView()
                .tabItem {
                    Label("Saved", systemImage: "star.fill")
                }
                .tag(1)
        }
    }
}
```

- [ ] **Step 2: Build and verify**

Open the project in Xcode and build (`Cmd+B`). Expected: build succeeds with no errors. The app should behave identically to before — tabs switch normally.

- [ ] **Step 3: Commit**

```bash
git add HeroDirt/ContentView.swift
git commit -m "feat: bind TabView selection to state in ContentView"
```

---

### Task 2: Add pendingPlace binding to MapExploreView

**Files:**
- Modify: `HeroDirt/Views/MapExploreView.swift`
- Modify: `HeroDirt/ContentView.swift`

- [ ] **Step 1: Add `@Binding var pendingPlace: Place?` to MapExploreView**

In `MapExploreView.swift`, add the binding property directly after the `@EnvironmentObject` line (line 71):

```swift
@Binding var pendingPlace: Place?
```

The top of `MapExploreView` should now read:

```swift
struct MapExploreView: View {
    @EnvironmentObject private var placeStore: PlaceStore
    @Binding var pendingPlace: Place?

    @State private var cameraPosition: MapCameraPosition = .automatic
    // ... rest unchanged
```

- [ ] **Step 2: Add onChange handler for pendingPlace**

In `MapExploreView.swift`, add this modifier inside the `MapReader` body, alongside the other `.onChange` modifiers (after the existing `onChange(of: overlayVisible)` around line 213):

```swift
.onChange(of: pendingPlace) { _, place in
    guard let place else { return }
    selectedCoordinate = place.coordinate
    selectedPlaceID = place.id
    selectedMapItem = nil
    hasSelection = false
    showingSheet = true
    pendingPlace = nil
}
```

- [ ] **Step 3: Fix centerAboveSheet to handle nil visibleRegion**

Replace the existing `centerAboveSheet` function (around line 271) with this version that falls back to a default span when `visibleRegion` is nil (which happens when the tab was just switched and the map hasn't reported its region yet):

```swift
private func centerAboveSheet(_ coordinate: CLLocationCoordinate2D) {
    let span = visibleRegion?.span ?? MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    let newCenter = CLLocationCoordinate2D(
        latitude: coordinate.latitude - span.latitudeDelta * 0.25,
        longitude: coordinate.longitude
    )
    withAnimation(.easeInOut(duration: 0.4)) {
        cameraPosition = .region(MKCoordinateRegion(center: newCenter, span: span))
    }
}
```

- [ ] **Step 4: Update ContentView to pass pendingPlace binding**

In `HeroDirt/ContentView.swift`, add `@State private var pendingPlace: Place? = nil` and pass it to `MapExploreView`:

```swift
import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    @State private var pendingPlace: Place? = nil

    var body: some View {
        TabView(selection: $selectedTab) {
            MapExploreView(pendingPlace: $pendingPlace)
                .tabItem {
                    Label("Map", systemImage: "map")
                }
                .tag(0)
            SavedPlacesView()
                .tabItem {
                    Label("Saved", systemImage: "star.fill")
                }
                .tag(1)
        }
    }
}
```

- [ ] **Step 5: Build and verify**

Build (`Cmd+B`). Expected: build succeeds with no errors. The app behaves identically to before — tapping pins on the map still works, camera still flies.

- [ ] **Step 6: Commit**

```bash
git add HeroDirt/Views/MapExploreView.swift HeroDirt/ContentView.swift
git commit -m "feat: add pendingPlace binding to MapExploreView for cross-tab navigation"
```

---

### Task 3: Add onSelectPlace callback to SavedPlacesView and wire it up

**Files:**
- Modify: `HeroDirt/Views/SavedPlacesView.swift`
- Modify: `HeroDirt/ContentView.swift`

- [ ] **Step 1: Add onSelectPlace parameter to SavedPlacesView**

In `SavedPlacesView.swift`, add the callback property directly after the `@EnvironmentObject` line (line 5):

```swift
var onSelectPlace: (Place) -> Void
```

The top of `SavedPlacesView` should now read:

```swift
struct SavedPlacesView: View {
    @EnvironmentObject private var placeStore: PlaceStore
    var onSelectPlace: (Place) -> Void

    @State private var rainfallData: [UUID: RainfallSummary] = [:]
    // ... rest unchanged
```

- [ ] **Step 2: Wrap PlaceRow in a Button to handle taps**

In `SavedPlacesView.swift`, replace the `PlaceRow(...)` call and its `.swipeActions` block (lines 25–44) with a `Button` wrapping:

```swift
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
```

- [ ] **Step 3: Update ContentView to pass the callback**

In `HeroDirt/ContentView.swift`, pass `onSelectPlace` to `SavedPlacesView`:

```swift
import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    @State private var pendingPlace: Place? = nil

    var body: some View {
        TabView(selection: $selectedTab) {
            MapExploreView(pendingPlace: $pendingPlace)
                .tabItem {
                    Label("Map", systemImage: "map")
                }
                .tag(0)
            SavedPlacesView(onSelectPlace: { place in
                pendingPlace = place
                selectedTab = 0
            })
            .tabItem {
                Label("Saved", systemImage: "star.fill")
            }
            .tag(1)
        }
    }
}
```

- [ ] **Step 4: Build and verify**

Build (`Cmd+B`). Expected: build succeeds with no errors.

- [ ] **Step 5: Test the feature on simulator or device**

1. Run the app. Save at least one place via the map (long-press → tap star).
2. Switch to the Saved tab.
3. Tap a PlaceRow.
4. Expected: app switches to the Map tab, the bottom sheet opens for that place, and the camera flies to the place with animation.
5. Verify swipe-to-delete and swipe-to-rename still work on PlaceRow items.
6. Verify tapping pins directly on the map still works as before.

- [ ] **Step 6: Commit**

```bash
git add HeroDirt/Views/SavedPlacesView.swift HeroDirt/ContentView.swift
git commit -m "feat: navigate to map with place selected when tapping a saved place row"
```
