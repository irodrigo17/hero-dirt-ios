# Hero Dirt iOS — CLAUDE.md

## Build & run

```bash
xcodegen generate          # regenerate .xcodeproj after adding/removing/moving files
xcodebuild -scheme HeroDirt -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

Always run `xcodegen generate` after adding, removing, or moving Swift source files.

## XcodeBuildMCP

Use the `xcodebuildmcp-cli` skill before calling any XcodeBuildMCP tools.

## Architecture

UIKit + SwiftUI hybrid. `UIKitMapView` is a `UIViewRepresentable` wrapping `MKMapView` — this is intentional for `MKOverlayRenderer`, `UISearchController`, and precise tap gesture handling. All other UI is SwiftUI.

Entry point: `HeroDirtApp` → `ContentView` → `MapView` → `UIKitMapView` (map) + `SheetView` (bottom sheet).

Shared state injected via `.environmentObject`: `PlaceStore`, `MapItemCache`.

## Key files

| File | Role |
|------|------|
| `Views/UIKitMapView.swift` | MKMapView wrapper — annotations, overlay renderer, gestures, search |
| `Views/MapView.swift` | Top-level SwiftUI view, owns `RainfallGridService` and overlay state |
| `Views/SheetView.swift` | Bottom sheet: saved places, search results, overlay controls |
| `Views/PlaceDetailsView.swift` | Location detail: rainfall, forecast, dirt condition, save/rename |
| `Services/RainfallGridService.swift` | Heatmap engine: grid fetch, bitmap render, caching |
| `Services/WeatherService.swift` | Open-Meteo API client (rainfall history + forecast) |
| `Services/SoilService.swift` | ISRIC SoilGrids API client |
| `Services/PlaceStore.swift` | Saved places CRUD + JSON persistence |
| `project.yml` | XcodeGen project definition |

## External APIs

- **Open-Meteo** — rainfall history and forecast, free, no key
- **ISRIC SoilGrids** — soil texture, free, no key
- **Apple MapKit** — map, search, geocoding
