# App Store metadata — Hero Dirt

Copy-paste values for App Store Connect. Character limits in brackets.

## App information

| Field | Value |
|---|---|
| Name [30] | **Hero Dirt: Trail Conditions** (27). Fallback if taken: *Hero Dirt – MTB Trail Weather* (29) |
| Subtitle [30] | **Know when trails are ridable** (29) |
| Bundle ID | `com.herodirt.app` |
| SKU | `herodirt-ios-001` |
| Primary category | Weather |
| Secondary category | Sports |
| Content rights | Does not contain, show, or access third-party content (weather data is fetched from APIs, not displayed as third-party content) |
| Age rating | 4+ (answer "None" to every questionnaire item) |
| Price | Free, no in-app purchases |
| Copyright | 2026 Ignacio Rodrigo |
| Support URL | https://github.com/irodrigo17/hero-dirt-ios/issues |
| Marketing URL (optional) | https://github.com/irodrigo17/hero-dirt-ios |
| Privacy Policy URL | https://github.com/irodrigo17/hero-dirt-ios/blob/main/PRIVACY.md |

## Promotional text [170]

> Rain last night? Hero Dirt estimates whether your favorite trails are soaked, muddy, or perfectly tacky — so you ride on the good days and keep the trails in shape.

(167)

## Description [4000]

> Hero dirt: that perfect, tacky, grippy trail you get a day or two after the rain. Hero Dirt helps mountain bikers find it.
>
> Save the trails you ride and see at a glance how each one is doing: Soaked, Muddy, Hero Dirt, Dry, or Dusty. Hero Dirt combines recent rainfall, how fast the ground is drying out, and the type of soil at each spot to estimate trail conditions — and tells you why.
>
> WHEN WILL IT BE RIDABLE?
> • Every saved trail shows its condition today and for each of the next 7 days
> • One line tells you what to do: "Hero dirt by Saturday", "Rain tomorrow, ride today", "Muddy all week"
> • A wetness chart shows the last two weeks and the week ahead, with the hero dirt zone marked
>
> TRAIL CONDITIONS AT A GLANCE
> • Condition, last rain, and rainfall for today, 2, 3, and 7 days for every saved trail
> • A clear explanation: how wet the ground is, what the dirt is like, and how fast it's drying
> • Rain on the way: forecast totals for the next week
>
> RAIN MAP
> • See where it rained over the last 1, 2, 3, or 7 days with a smooth, color-coded overlay
> • Pan anywhere to check conditions before you drive to the trailhead
>
> FIND AND SAVE TRAILS
> • Search for parks, preserves, and trailheads, tap a spot on the map, or drop a pin anywhere
> • Reorder your trails, rename them, and get driving directions in Apple Maps
> • Map pins are colored by trail condition
>
> TUNED TO YOUR TRAILS
> • Soil type comes from global soil maps, so sandy trails dry faster than clay
> • Know your trail better? Set the dirt type and how much sun it gets
>
> MADE FOR RIDERS
> • Rain in inches or millimeters
> • Saved trails sync with iCloud and come back if you reinstall
> • Works beautifully in portrait and landscape, including side-by-side on bigger screens
> • Free, no ads, no account, and open source
>
> Please always respect trail closures. Hero Dirt gives you an estimate based on weather data — shade, slope, drainage, and trail surface make a big difference, and land managers have the final word.
>
> Weather data: Apple Weather and Open-Meteo. Soil data: ISRIC SoilGrids.

(~1,850 characters)

## Keywords [100]

```
mtb,mountain bike,trail,mud,rain,weather,dirt,cycling,bike,conditions,soil,forecast,ride,hiking
```

(97). Don't repeat words already in the name/subtitle — Apple indexes those separately.

## What's New (first release)

> First release! Track trail conditions for your favorite spots, check the rain map, and find hero dirt.

## App Review information

- **Sign-in required:** No.
- **Notes for the reviewer:**
  > Hero Dirt estimates mountain bike trail conditions from recent rainfall and soil data. No account is needed. To try it: search for a park (e.g. "Golden Gate Park") or long-press anywhere on the map, then tap Save to add it to your saved places. Tap the cloud button to show the rain map. Location permission is optional and only used to center the map. Saved places sync through the user's own iCloud key-value storage. Weather forecasts come from Apple WeatherKit (attribution shown on the forecast card).
- **Contact:** your name, phone, email.

## App Privacy (nutrition label)

**Data Not Collected.** Rationale for each item App Store Connect asks about:

| Data | Answer | Why |
|---|---|---|
| Location | Not collected | Used on device to center the map. Coordinates of places you look at are sent to weather/soil APIs only to answer that request (real-time servicing), not stored or linked to you by the app. |
| Contacts, Identifiers, Usage Data, Diagnostics | Not collected | Telemetry stays on device (unified log + local counts); MetricKit diagnostics are stored locally only. |
| User content (saved places) | Not collected | Stored in the user's own iCloud account, which the developer can't access. |
| Tracking | No | No ads, no third-party SDKs, no cross-app tracking. |

If you later forward telemetry to a backend (e.g. TelemetryDeck), update this to "Usage Data – not linked to you – Analytics".

## Export compliance

`ITSAppUsesNonExemptEncryption = NO` is already in Info.plist (only standard HTTPS), so uploads skip the encryption questionnaire.

## Screenshots

Required for iPhone: at least one **iPhone with Dynamic Island (medium display)** set; App Store Connect scales sets down for other sizes. Optional iPhone Duo sets add the "optimized for iPhone Duo" badge (and are required from April 2027 for apps built with the iOS 27.1 SDK). The app is iPhone-only, so no iPad screenshots. All PNG, opaque, captioned; upload each folder in file order.

| App Store Connect slot | Size (px) | Folder (`docs/app-store/screenshots/`) |
|---|---|---|
| iPhone with Dynamic Island, medium (required) | 1206 × 2622 | `iphone-6.3/` (5) |
| iPhone with Dynamic Island, large | 1320 × 2868 | `iphone-6.9/` (5) |
| iPhone Duo, outer display | 1398 × 2034 | `iphone-duo-outer/` (4) |
| iPhone Duo, inner display portrait | 2007 × 2853 | `iphone-duo-inner-portrait/` (1) |
| iPhone Duo, inner display landscape | 2853 × 2007 | `iphone-duo-inner-landscape/` (2) |

iPhone order: 1. Know when your trails are ridable (My Trails) · 2. Hero dirt? Go ride. (details) · 3. Plan the week ahead (outlook + wetness chart) · 4. See where it rained (rain map) · 5. Made for riders, day or night (dark mode).

Regenerate: build the app onto the simulators (iPhone 17 Pro, iPhone 17 Pro Max, iPhone Duo), then
`AI_AGENT=... /usr/bin/python3 screenshots/capture.py <p17|pm|duo> screenshots/raw` (runs the app with `-useFakeServices -startInList`, status bar 9:41) and
`/usr/bin/python3 screenshots/frame.py screenshots/raw screenshots`.

## Creative assets (iOS 27 product page header + search results)

Opaque PNGs in `docs/app-store/creative/`, with the icon, name and tagline inside Apple's "art safe area" (measured from Apple's templates); the strata background bleeds to every edge so any crop looks intentional.

| Slot | File | Size |
|---|---|---|
| Product page **Header** | `header-21x9-3840x1646.png` (or the universal file) | 3840 × 1646 |
| **Search Results** | `search-results-3x2-3840x2560.png` (icon + name + two real trail cards) | 3840 × 2560 |
| Either slot (universal 16:9) | `universal-16x9-5244x2950.png` | 5244 × 2950 |

Use the Preview button in App Store Connect to check crops on different devices. Regenerate with `/usr/bin/python3 creative/make_creative_assets.py icon/Icon-1024-AppStore.png screenshots/raw/pm-1-list.png creative`.

## App icon

Xcode builds the icon from the asset catalog (`AppIcon` 1024 with dark and tinted variants). Every size is also exported in `docs/app-store/icon/` (`Icon-1024-AppStore.png` is the App Store icon).

## Checklist before submitting

- [ ] CloudKit schema: no longer needed (saved places use the iCloud key-value store); remove the CloudKit capability once testers have run the one-time import build.
- [ ] Remove the `aps-environment` entitlement (no push notifications).
- [ ] Merge `PRIVACY.md` to `main` so the privacy policy URL resolves.
- [ ] Bump `CURRENT_PROJECT_VERSION` for each upload (Xcode can do this automatically when distributing).
