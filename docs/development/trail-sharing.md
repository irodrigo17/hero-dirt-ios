# Trail sharing

Implemented locally:

- More → Share Trail opens the native iOS share sheet with a rendered condition image and text.
- The image includes the destination name, estimated conditions, outlook, recent rain, and sharing time.
- `herodirt://trail?lat=...&lon=...&name=...` opens the destination in an installed Hero Dirt app. Opening a link does not automatically save it.
- An accompanying `https://maps.apple.com/` link lets a recipient view the destination without installing Hero Dirt.
- Shared text also includes [Get Hero Dirt](https://apps.apple.com/app/id6770195112), using the Apple ID supplied by the developer. This URL can ship before release; recipients can use the listing once it is public, including an approved pre-order listing.
- Link parsing rejects missing, duplicate, non-finite, and out-of-range coordinates. Names and query values are encoded with URLComponents.

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
