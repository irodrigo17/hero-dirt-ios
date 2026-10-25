# Trail sharing

Implemented locally:

- More → Share Trail opens the native iOS share sheet with a rendered condition image and text.
- The image includes the destination name, estimated conditions, outlook, recent rain, and sharing time.
- `herodirt://trail?placeID=...` shares only the Apple Maps place identifier when available. The receiving app resolves it asynchronously through MapKit before opening details, with a loading indicator and an error if lookup fails.
- When no place identifier is available, the link uses `herodirt://trail?lat=...&lon=...&name=...`. Previously shared coordinate links remain supported. Opening either kind of link does not automatically save it.
- Shared text no longer includes the separate “View location” / Apple Maps link.
- Shared text also includes [Get Hero Dirt](https://apps.apple.com/app/id6770195112), using the Apple ID supplied by the developer. This URL can ship before release; recipients can use the listing once it is public, including an approved pre-order listing.
- Link parsing rejects empty/duplicate place IDs, mixed ID-and-coordinate payloads, and missing, duplicate, non-finite, or out-of-range coordinates. Names and query values are encoded with URLComponents.

The app does not send a message itself. The person sharing chooses a destination and completes the action in the system share sheet.

## Remaining: one HTTPS link with installation fallback

A custom scheme cannot take an uninstalled app to the App Store automatically. The App Store URL is now configured as `https://apps.apple.com/app/id6770195112`. A controlled HTTPS host for a landing page/universal links is still needed. Listing availability has not been verified; an absent public lookup result does not prevent assigning or configuring the app's Apple ID before release.

After a host is available:

1. Choose the owned HTTPS route, for example `/trail` on the selected domain; validate and URL-encode the destination payload.
2. Host the Apple App Site Association file with the actual app identifier, and add the corresponding Associated Domains entitlement.
3. Extend the parser to accept that exact trusted HTTPS host and path, then handle universal links as well as the existing custom scheme.
4. Make the landing page show the destination, an Open in Hero Dirt button, the actual App Store link, and an Apple Maps alternative. Ensure displayed names are escaped and coordinates validated.
5. Share that HTTPS link, and verify installed/uninstalled behavior on physical iPhones, including cold and warm launches, denied app-opening prompts, and return from the App Store.

No website has been published and no Associated Domains entitlement has been added without a verified host.
