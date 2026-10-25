# First-share latency investigation

The developer reports a pause both before presentation and while the first share sheet populates. Sharing another trail immediately afterward is fast even though the condition image is new. This is consistent with first-use initialization in the share system; it does not establish dynamic library loading as the cause.

Debug builds log two non-sensitive durations under subsystem `com.herodirt.app`, category `Sharing`:

- `sharing phase=render_condition_image elapsed_ms=...`: synchronous SwiftUI ImageRenderer work.
- `sharing phase=create_share_controller elapsed_ms=...`: UIActivityViewController construction.

These intervals do **not** measure asynchronous activity discovery, remote share-extension UI, image representation requests made later by receiving apps, or the entire presentation animation. They are excluded from Release logging. No hidden share sheet or dummy image is generated to prewarm frameworks, and the outgoing image/App Store URL payload is unchanged.

In a fresh app process on the dedicated iOS 26.4 simulator (October 24, 2026), three different trails produced these measurements:

| Phase | First share | Second trail | Third trail |
| --- | ---: | ---: | ---: |
| Image render | 31.85 ms | 7.66 ms | 7.37 ms |
| Controller construction | 1.72 ms | 0.17 ms | 0.11 ms |

The UI automation successfully presented/dismissed all three sheets. Its end-to-end tap-to-Copy measurements were around three seconds each, including XCTest synchronization and animations; those are not precise user-perceived latency measurements. The large first-share delay reported on the phone was not reproduced here.

Next device check: rebuild Debug, launch a fresh process, share one trail and then a different trail, and compare the `sharing phase=` entries with the observed pause. If both durations stay short during a long pause, profile system presentation/activity discovery with Instruments. Compare launching directly from the Home Screen with launching under the debugger, and verify a Release/TestFlight build before treating the issue as a debugger-only effect.
