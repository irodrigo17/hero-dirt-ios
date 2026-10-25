# Localization

Hero Dirt supports English (`en`, the development/fallback language), Spanish (`es`), French (`fr`), German (`de`), Brazilian Portuguese (`pt-BR`), and Japanese (`ja`). iOS selects the app language from the user's preferred languages or the app-specific Language setting in Settings. The app has no separate language picker.

## Resources and implementation

- `HeroDirt/Localizable.xcstrings`: interface text, errors, condition descriptions and outlooks, accessibility text, feedback forms, and generated share-card captions.
- `HeroDirt/InfoPlist.xcstrings`: the optional location permission explanation for map centering and driving ETA.
- `project.yml`: development language, supported regions, and compiler string extraction. Regenerate the Xcode project with `xcodegen generate` after adding resources or Swift files.
- `scripts/check-localizations.py`: checks all six language variants, translation status, and printf argument positions/types, including plural forms. Runs in GitHub Actions.

SwiftUI text literals use native catalog lookup. String-valued model labels and runtime summaries use `String(localized:)`. Shared view components such as `CardHeader` take `LocalizedStringKey`, so their labels also participate in compiler extraction. Outlook sentences are translated as complete phrases, allowing Japanese to put the weekday before the condition. Relative rain-day counts have catalog plural variations. Full weekday names are used in forecast sentences; the compact day chips retain short weekday labels. Date/weekday names, driving durations, percentage values, and rainfall decimal separators use system locale formatting. Rain units still follow the region's measurement system unless overridden in About.

The app brand **Hero Dirt** remains unchanged. The condition named “Hero Dirt” is translated as ideal riding soil; these uses are distinct. User-entered names and MapKit place names are not translated by the app. Soil/exposure enum raw values and internal soil classifications remain English identifiers for compatibility with saved/iCloud data. Identifiers, URLs, symbol names, and telemetry event keys are not translated. App Store descriptions/screenshots and the repository's Markdown documents are separate from app localization and have not been translated.

## Updating strings

Use Xcode's String Catalog editor and build with `SWIFT_EMIT_LOC_STRINGS=YES` (already enabled). Translate new entries in all five additional languages, with English as the source. For command-line extraction, build first, then use `xcrun xcstringstool sync` on `Localizable.xcstrings` with the app target's emitted `.stringsdata` files from DerivedData. Do not include the unit/UI test target's extraction files. Review new/stale entries before committing; do not translate technical identifiers accidentally.

Preserve every interpolation's argument number and type. Numbered substitutions such as `%1$@` and `%2$@` allow reordering. Avoid concatenating English word fragments to form sentences. Add plural variations where counts can be singular; Japanese generally uses only the `other` category. Keep translator context for overloaded terms such as the ideal-soil condition.

Run:

```sh
python3 scripts/check-localizations.py
```

Build/test the `HeroDirt` scheme on an available iOS simulator. `LocalizationTests` checks that the compiled language bundles and permission table exist, runtime substitutions/plurals resolve, regional decimal separators work, and saved soil settings retain their raw values. `LocalizationUITests` opens the saved-trail list, details, soil settings, and About in all five languages and records screenshots. Existing English tests remain regression coverage. Keep normal code signing enabled and verify a normal launch without fake services.

For manual checks, set the scheme's App Language/App Region or use Simulator launch arguments, for example:

```sh
xcrun simctl launch --terminate-running-process SIMULATOR_UDID com.herodirt.app \
  -AppleLanguages '(ja)' -AppleLocale ja_JP
```

Replace the simulator identifier; do not erase an existing simulator or delete user data to change languages. Omit the language arguments to return to device defaults. Native-speaker review of MTB terminology remains useful; these are initial translations, not a claim of professional linguistic review. Also check larger text sizes and a delivered share image on a physical iPhone before release.

Apple references: [String Catalogs](https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog), [Preparing text for translation](https://developer.apple.com/documentation/xcode/preparing-your-apps-text-for-translation).
