# Saved Places → Map Navigation

**Date:** 2026-05-05  
**Status:** Approved

## Goal

Tapping a `PlaceRow` in `SavedPlacesView` switches to the Map tab, selects the place pin, and opens the bottom sheet — with the camera flying to the place.

## Architecture

Navigation state (`selectedTab`, `pendingPlace`) lives in `ContentView`, which owns both tabs. This keeps the data store (`PlaceStore`) free of UI concerns and avoids a new type.

## Component Changes

### ContentView

- Add `@State private var selectedTab = 0`
- Add `@State private var pendingPlace: Place? = nil`
- Bind `TabView` selection to `$selectedTab`
- Pass `pendingPlace: $pendingPlace` to `MapExploreView`
- Pass `onSelectPlace` callback to `SavedPlacesView` that sets `pendingPlace = place` and `selectedTab = 0`

### MapExploreView

- Add `@Binding var pendingPlace: Place?` parameter
- Add `onChange(of: pendingPlace)` handler that:
  1. Sets `selectedCoordinate`, `selectedPlaceID`, clears `selectedMapItem` and `hasSelection`
  2. Sets `showingSheet = true` — triggering the existing `centerAboveSheet()` via its `onChange(of: showingSheet)` handler
  3. Nils out `pendingPlace` to reset the binding
- If `visibleRegion` is nil when `centerAboveSheet()` runs (tab just switched, map not yet settled), fall back to setting `cameraPosition` directly to a region centred on the coordinate

### SavedPlacesView

- Add `var onSelectPlace: (Place) -> Void` parameter
- Wrap each `PlaceRow` in a `Button` (or add `.onTapGesture`) inside the `ForEach`, calling `onSelectPlace(place)`
- Swipe actions (rename, delete) are unaffected

### PlaceRow

No changes required.

## Data Flow

```
User taps PlaceRow
  → SavedPlacesView calls onSelectPlace(place)
    → ContentView sets pendingPlace = place, selectedTab = 0
      → Tab switches to MapExploreView
        → MapExploreView.onChange(of: pendingPlace) fires
          → Sets selectedCoordinate, selectedPlaceID, showingSheet = true
            → onChange(of: showingSheet) calls centerAboveSheet()
              → Camera flies to place, sheet appears
          → pendingPlace = nil
```

## Edge Cases

- **`visibleRegion` is nil on tab switch:** Fall back to `cameraPosition = .region(MKCoordinateRegion(center: coordinate, span: <default span>))` so the camera still moves to the place.
- **Swipe actions:** Existing `.swipeActions` on `PlaceRow` (rename, delete) remain separate from the tap gesture and are unaffected.
- **Empty places list:** No tap targets exist; `ContentUnavailableView` is shown — no change needed.
