# Hero Dirt iOS

A native iOS app that helps mountain bikers and trail runners decide if conditions are good to ride. Search for outdoor places, save your favorites, and get rainfall history, rain forecast, and a dirt condition estimate based on soil moisture modeling.

## Features

- **Rainfall overlay** — Bitmap-rendered heatmap using per-pixel bilinear interpolation and Gaussian blur. Supports time period switching (1d/2d/3d/7d) and an opacity slider.
- **Dirt condition** — Estimates trail rideability using a soil moisture balance model driven by rainfall and evapotranspiration data. Soil type can be overridden per place.
- **Rain forecast** — Shows predicted precipitation for the next 1, 2, 3, and 7 days via Apple WeatherKit.
- **iCloud sync** — Saved places sync across devices via CloudKit.
- **Place search** — `UISearchController`-powered search using `MKLocalSearch` with outdoor place prioritization (parks, forests, trails, campgrounds). Results are biased toward the current map viewport.
- **Tap-to-inspect** — Tap anywhere on the map to see rainfall history, forecast, and dirt condition for that location.
- **Saved places** — Save locations with custom names. Each saved place shows as a marker on the map.

## Architecture

The app uses a UIKit+SwiftUI hybrid. `UIKitMapView` is a `UIViewRepresentable` wrapping `MKMapView` — this gives precise control over `MKOverlayRenderer`, gesture recognizers, and `UISearchController`. All other UI is SwiftUI.

### Layers

**App** — `HeroDirtApp` is the entry point. It creates `PlaceStore` and `MapItemCache` as `@StateObject`s and injects them into the SwiftUI environment. `ContentView` renders `MapView`.

**Views**

| View | Role |
|------|------|
| `MapView` | Top-level SwiftUI view. Hosts `UIKitMapView` and the bottom sheet (`SheetView`). Owns the rainfall grid service and overlay state. |
| `UIKitMapView` | `UIViewRepresentable` wrapping `MKMapView`. Handles annotations, the rainfall bitmap overlay via `MKOverlayRenderer`, tap gestures, and `UISearchController` integration. |
| `SheetView` | Bottom sheet with tabs: saved places list, search results, and overlay controls. |
| `PlaceDetailsView` | Detail sheet for a tapped or selected location. Fetches and displays rainfall history, rain forecast, and dirt condition. Provides save/unsave/rename actions. |
| `SavedPlacesListView` | Lists saved places with concurrently-fetched rainfall summaries and soil data. |
| `DirtConditionCardView` | Card displaying the dirt condition estimate with expandable detail and a soil type override button. |
| `RainfallCardView` | Card displaying a `RainfallSummary` (four timeframe tiles + days since last rain). |
| `RainForecastCardView` | Card displaying forecasted precipitation for the next 1/2/3/7 days. |
| `RainfallOverlaySheet` | Controls for the heatmap: timeframe picker, opacity slider, and color legend. |
| `SearchResultsView` | List of `MKMapItem` search results. |
| `AboutView` | App info, iCloud sync status, and legal links. |

**Services**

| Service | Role |
|---------|------|
| `RainfallGridService` | The heatmap engine. Divides the visible map region into a ~12×12 grid, fetches each cell via `WeatherService`, caches results (15-min TTL), renders an upscaled bilinearly-interpolated RGBA bitmap with Gaussian blur, and caches rendered `UIImage`s per timeframe. |
| `WeatherService` | Stateless API client (enum namespace). Fetches rainfall history and rain forecast from Open-Meteo. |
| `SoilService` | Fetches soil texture data from the ISRIC SoilGrids API and caches it. Used for the dirt condition model. |
| `PlaceStore` | The only shared mutable state. `ObservableObject` with a `@Published` array of `Place` objects. Provides CRUD, proximity search, and persists to `saved_places.json` via `JSONEncoder`. |
| `MapItemCache` | Caches `MKMapItem` lookups to avoid redundant geocoding across views. |
| `RainfallColorScale` | Pure mapping from rainfall mm to RGBA color. Pre-computes RGBA components for efficient per-pixel bitmap rendering. |

**Models**

| Model | Role |
|-------|------|
| `Place` | A saved location (UUID, name, lat/lon). `Codable` for persistence. |
| `DailyRainfall` | A single day's rainfall record (date + mm amount). |
| `RainfallSummary` | Aggregated rainfall: 1/2/3/7-day totals and days since last rain. |
| `RainForecast` | Forecasted precipitation for the next 1/2/3/7 days. |
| `RainfallTimeframe` | Enum (1d/2d/3d/7d) used to select which summary field to display on the overlay. |
| `RainfallGridBounds` | Lat/lon bounding box for positioning the overlay image on the map. |
| `SoilData` | Raw soil texture fractions (sand/clay) from the SoilGrids API. |
| `SoilOverride` | User-specified texture class and exposure for a place, overriding the API data. |
| `DirtConditionResult` | Output of the soil moisture model: a condition label and the underlying computed values. |

### Key data flows

**Heatmap rendering** — When the map camera moves, `MapView` calls `RainfallGridService.updateRegion()` (debounced 500 ms). The service builds a grid, fetches uncached cells via `WeatherService`, renders a bilinearly-interpolated RGBA bitmap colored by `RainfallColorScale`, and publishes the result as a `UIImage`. `UIKitMapView` positions it on the map via `MKOverlayRenderer`.

**Tap-to-inspect** — A `UITapGestureRecognizer` in `UIKitMapView` converts screen coordinates to lat/lon. `MapView` presents `PlaceDetailsView`, which independently calls `WeatherService` for rainfall and forecast, `SoilService` for soil data, and reverse-geocodes the location via `MKLocalSearch`.

**Saved places** — `PlaceStore` is injected via `.environmentObject` from the root. `PlaceDetailsView` saves/removes places, `UIKitMapView` reads them for map annotations, and `SavedPlacesListView` lists them with concurrently-fetched data.

## Building

```bash
xcodegen generate
xcodebuild -scheme HeroDirt -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

Or open `HeroDirt.xcodeproj` in Xcode after running `xcodegen generate`.

## APIs

| API | Purpose |
|-----|---------|
| [Open-Meteo](https://open-meteo.com/) | Historical daily rainfall (free, no API key) |
| [ISRIC SoilGrids](https://soilgrids.org/) | Soil texture data (free, no API key) |
| Apple WeatherKit | Rain forecast (requires Apple Developer account) |
| Apple CloudKit | iCloud sync for saved places |
| Apple MapKit | Map rendering, search, and geocoding |

## License

MIT
