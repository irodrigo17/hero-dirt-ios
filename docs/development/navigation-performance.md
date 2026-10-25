# First detail-navigation diagnostics

Debug builds log anonymous `navigation session=... phase=...` entries under subsystem `com.herodirt.app`, category `NavigationPerformance`. No trail names, saved IDs, coordinates, or condition contents are logged. Release builds do not run the logging or responsiveness probe.

## Capture on an iPhone

Rebuild Debug and launch a fresh process. Open one saved trail from the list, return, and open another trail. Paste the `navigation` lines from both sessions, including any `main_actor_queue_delay` entries. Avoid interacting with other screens during the capture. The physical-device freeze remains unconfirmed by the simulator and is not marked fixed by these diagnostics.

- `selection_received`: the list selection binding receives a different nonempty selection, before building the selected detail view. It does not measure touch processing before the selection changes.
- `detail_appeared`, `skeleton_appeared`, `conditions_load_started`, `conditions_state_applied`, and `chart_appeared`: elapsed time since selection. An appearance callback is not a guarantee that the corresponding frame has reached the display.
- `sync_ms`: synchronous work for MapKit request construction, condition/outlook/trend calculations, or the condition telemetry update. These measurements do not include deferred SwiftUI layout, UIKit navigation internals, or GPU rendering.
- `wall_ms`: elapsed time for metadata, website preparation, driving ETA, soil resolution, and the combined conditions load. This includes time suspended waiting for requests; a large number alone does **not** establish that the main thread was blocked. Soil starts independently and may finish after the combined weather load.
- `main_actor_queue_delay`: a background task requests a tiny main-actor callback every 50 ms and logs delays of at least 100 ms. It watches for up to four seconds after selection and restarts for four seconds when condition data is applied, covering the initial transition and the first loaded-card/chart layout. Starting another navigation or another probe window cancels the previous probe. It stops when a callback finds the app inactive. No network request is issued by the probe.

Queue delays indicate reduced main-actor responsiveness; they can include OS scheduling pressure and are not a sampled stack trace or definitive identification of the blocking function. A rendering hitch can also occur without a long main-actor delay. If synchronous phases are short but the animation freezes, use Instruments Time Profiler/Animation Hitches to identify framework/layout/rendering work. Do not add together overlapping async phases or repeated model evaluations.

## Simulator validation (October 24, 2026)

A fresh fake-service process on the dedicated iPhone 17 Pro / iOS 26.4 simulator logged distinct sessions for two trail openings. The first detail appeared around 56 ms after selection and the chart appearance callback around 163 ms; the second detail appeared around 50 ms and its chart around 72 ms. No main-actor queue delay above 100 ms was reported in that run. These fake-service simulator numbers do not reproduce the iPhone's reported freeze or account for live-service initialization.

Both navigation checks and a separate normal launch passed. Debug and Release builds passed. The temporary two-trail diagnostic UI test was removed after verification; the existing regression tests remain unchanged.
