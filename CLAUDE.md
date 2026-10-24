# Hero Dirt iOS — CLAUDE.md

## Build & run

```bash
xcodegen generate          # regenerate .xcodeproj after adding/removing/moving files
xcodebuild -scheme HeroDirt -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Always run `xcodegen generate` after adding, removing, or moving Swift source files.

Keep normal code signing enabled for simulator builds. `CODE_SIGNING_ALLOWED=NO`
omits the iCloud entitlements and causes normal startup to crash in CloudKit.
Verify a normal launch without `-useFakeServices` as well as fake-service UI tests.

## XcodeBuildMCP

Use the `xcodebuildmcp-cli` skill before calling any XcodeBuildMCP tools.

## Architecture

UIKit + SwiftUI hybrid. `UIKitMapView` is a `UIViewRepresentable` wrapping `MKMapView` — this is intentional for `MKOverlayRenderer` (the rain map image) and precise gesture handling. All other UI is SwiftUI.

Entry point: `HeroDirtApp` → `ContentView` → `MapView` → `UIKitMapView` (map) + `SheetView` (bottom sheet in portrait, sidebar in landscape / wide windows).

- State is `@Observable` throughout. Shared objects are injected with `.environment(_:)`: `PlaceStore`, `MapItemCache`.
- Services are injected through `EnvironmentValues`: `\.weather` (`WeatherProviding`) and `\.soil` (`SoilProviding`). Use fakes from `SampleData.swift` in previews and tests (`.previewEnvironment()`).
- Launch with `-useFakeServices` to run the app on sample data (no network, no iCloud).
- `MapModel` owns the map screen's state; the selection is a single `Selection` enum.

## Key files

| File | Role |
|------|------|
| `Views/MapView.swift` + `Views/MapModel.swift` | Map screen: layout (sheet vs split), selection, camera, rain overlay settings |
| `Views/UIKitMapView.swift` | MKMapView wrapper: annotations (animated diff), overlay renderer, gestures |
| `Views/SheetView.swift` | Saved places / search; map actions in the toolbar (stacked layout only) |
| `Views/PlaceDetailsView.swift` | Location detail: conditions, rain, forecast (+ Apple Weather attribution), save/rename |
| `Views/PlaceConditionsModel.swift` | Loads rain for the saved places list |
| `Services/RainfallGridService.swift` | Rain map: fixed-lattice grid, cache, background rendering |
| `Services/WeatherService.swift` | Open-Meteo client (observed rain, today only up to now) + WeatherKit forecast |
| `Services/SoilService.swift` | ISRIC SoilGrids client: disk cache, throttle (~5/min) |
| `Services/PlaceStore.swift` | Saved places in the iCloud key-value store (+ JSON backup), merge with tombstones |
| `Services/Providers.swift` / `SampleData.swift` | Service protocols, environment keys, fakes and sample data |
| `project.yml` | XcodeGen project definition (keep in sync with `project.pbxproj`) |

## External APIs

- **Open-Meteo** — rainfall history and forecast, free, no key
- **ISRIC SoilGrids** — soil texture, free, no key
- **Apple MapKit** — map, search, geocoding
