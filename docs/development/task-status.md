# Task-list status

Development branch: `codex/dev`. This tracks the user's screenshot list and subsequent refinements. Changes are committed locally; no deployment or push is implied.

| Requested item | Current result |
| --- | --- |
| Janky search animation | Native bottom-toolbar search on the main list, stable toolbar items during focus changes, a loading state instead of premature "No results", explicit errors, and cancellation of stale UI tasks and underlying MapKit requests. Focus/dismissal, text input, position and Dictation controls have simulator coverage. |
| Rename under More, plus settings/delete | Implemented with a deletion confirmation. |
| Map sheet matches main list | Both use the shared trail card, outlook, condition badge and daily strip; the map sheet uses the same title and search prompt. |
| Email alternative to GitHub feedback | Email Feedback at the bottom of About, addressed to `irodrigo17@gmail.com`; fallback offers copying the address when email cannot open. |
| Nearby recommendations | Plan only at the user's request. Must recommend popular, high-quality, MTB-specific rides; no generic park fallback. See [the recommendation plan](mtb-recommendations-plan.md). |
| Observed rain calendar and full forecast | Calendar covers the observed history the app currently fetches (roughly 30 days), including month navigation and explicit missing dates. Daily rain forecast retains all days supplied by Apple Weather, including precipitation chances. Historical browsing beyond that fetched window is not implemented. |
| Reorder trails | Native Edit/Done controls and drag handles on My Trails. Order persists locally and is shared with the map list. |
| Remove prominent Saved button | Saved places have no Saved/unsave action. Deletion lives under More and requires confirmation. |
| Tone down bright colors | Condition and rain-map colors adjusted roughly halfway between the original bright palette and the first muted version, with adaptive light/dark condition colors. No condition thresholds or meanings changed. |
| Main search at bottom | Native iOS bottom-toolbar search, with the standard keyboard and Dictation. |
| Voice search | Uses existing system keyboard Dictation; no custom audio recorder, speech engine, or app-specific audio permissions. The Dictate control is verified in main and map search keyboards; speech itself needs a physical-device check. |
| Share trail and condition image | More → Share Trail presents a native share sheet with an exportable image, text, an installed-app deep link using an Apple Maps place ID when available (coordinates/name otherwise), and App Store link using Apple ID `6770195112`. See [sharing implementation and remaining setup](trail-sharing.md). An HTTPS universal link with automatic App Store fallback still requires an owned domain; the listing must be public for recipients to use it. |
| Driving ETA | Car button shows driving time when available, falls back to Directions, and still opens driving navigation. |
| Open in Apple Maps / Weather | Open in Maps is under More. Apple Weather remains deferred as agreed because location-specific link behavior is unverified and the app is not bundled with the iOS simulator. A generic launcher that may display the wrong location has not been added. |
| Place website | Website under More when Apple Places provides an HTTP(S) URL. |
| Remove detail subtitle | Category/location subtitle removed from place details. |
| Small inline Save and animation | Save, driving time and More share a row. Saving fades/scales out Save while the other buttons expand, preserving loaded conditions. |
| Simulator launch crash | Normal simulator signing restored; normal-startup UI coverage added so fake-service tests cannot mask CloudKit startup problems. |

## Remaining external setup and decisions

- Approve a supported MTB data source and obtain appropriate API access before implementing recommendations. Current plan prioritizes access certainty and genuine rating/popularity signals.
- Choose a controlled HTTPS host to finish install fallback/universal links. The developer-supplied App Store URL is configured; public listing availability remains unverified.
- Verify a location-specific Apple Weather opening mechanism on a physical iPhone before adding its dedicated button.
- Decide whether the observed calendar should load older months on demand; the current implementation intentionally labels its available history rather than presenting missing dates as dry weather.

## Verification

The combined changes passed 167 unit tests and 14 simulator UI tests on the iPhone 17 Pro / iOS 26.4 test simulator. Additional dark-mode detail checks and the share-image/parser tests passed after the final icon-contrast adjustment. Normal simulator code signing remained enabled. Native speech transcription and installed/uninstalled universal-link behavior are physical-device follow-ups, not claimed as simulator-verified.

The place-ID sharing update passed 178 unit tests and five focused simulator UI checks (ID links, coordinate links, lookup failure/recovery, sharing, and normal startup). A separate live round-trip using Apple Park Visitor Center’s public place ID also passed; that network-dependent smoke check is not part of CI.
