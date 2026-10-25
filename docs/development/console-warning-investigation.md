# Device console warnings: chart anchors and search navigation

Investigated October 24, 2026, using the developer's physical-iPhone log excerpt. Validation used the dedicated iPhone 17 Pro simulator running iOS 26.4, built with the installed iOS 27.1 SDK. Physical-device confirmation is still required; the simulator result does not prove behavior on another OS build or explain the previously reported first-navigation pause.

## Chart axis labels

The log reports `Charts: Custom UnitPoint values are not supported in AxisValueLabel's anchor property`. Our chart did not supply custom UnitPoints: it left the axis-label anchor unspecified. Specify supported named anchors explicitly: `.leading` for the two vertical axes and `.top` for the date axis. This avoids relying on a computed default anchor. Chart/card navigation checks pass and the warning was absent from the final simulator log window. The original phone-only chart warning was not reproduced independently on this simulator, so regard this as a targeted mitigation pending an iPhone retest.

## Search navigation ownership

The physical log repeatedly reports `Ignoring searchBarPlacementBarButtonItem because its vending navigation item does not match the view controller's`.

The explicit `DefaultToolbarItem(kind: .search, placement: .bottomBar)` was redundant with the native search placement provided by `.searchable(..., placement: .automatic)`. Removing the explicit item stopped the mismatch warning in the checked simulator flows. The native bottom search field and keyboard Dictation remain available. Search remains attached to the list column; no UIKit introspection or replacement search field is used.

An experiment attaching searchable to the outer split view retained the mismatch and produced an additional `UIKitToolbar` view-hierarchy warning, so that placement change was discarded.

Validation covered list and map search, detail push/pop, rename/settings/delete through More, rain calendar/forecast sheets, and normal launch. No search-navigation mismatch, custom-axis-anchor warning, or UIKitToolbar hierarchy warning appeared after the final search configuration was installed. Other Apple framework diagnostic messages were not suppressed.

## Row gestures

Both the main list and the map saved-trails list use the same native swipe behavior:

- Swipe right: Directions (blue car action), opening Apple Maps in driving mode using the saved name and coordinates.
- Swipe left: the existing native Delete action.

Directions does not wait for metadata or weather. Rename remains in the place details More menu. A simulator integration check reveals both swipe actions in both lists and verifies that Directions hands off to Apple Maps.

References: [Apple search interface guidance](https://developer.apple.com/documentation/swiftui/adding-a-search-interface-to-your-app), [AxisValueLabel](https://developer.apple.com/documentation/charts/axisvaluelabel).
