# Trail sharing

Implemented locally:

- More → Share Trail opens the native iOS share sheet with a rendered condition image and text.
- The image includes the destination name, estimated conditions, outlook, recent rain, and sharing time.
- `herodirt://trail?lat=...&lon=...&name=...` opens the destination in an installed Hero Dirt app. Opening a link does not automatically save it.
- An accompanying `https://maps.apple.com/` link lets a recipient view the destination without installing Hero Dirt.
- Link parsing rejects missing, duplicate, non-finite, and out-of-range coordinates. Names and query values are encoded with URLComponents.

The app does not send a message itself. The person sharing chooses a destination and completes the action in the system share sheet.

## Remaining: one HTTPS link with installation fallback

A custom scheme cannot take an uninstalled app to the App Store. This needs a real public App Store URL and a controlled HTTPS host for a landing page/universal links. Apple's public lookup for `com.herodirt.app` returned no listing on October 24, 2026; no ID or hosted URL has been guessed.

After those are available:

1. Choose the owned HTTPS route, for example `/trail` on the selected domain; validate and URL-encode the destination payload.
2. Host the Apple App Site Association file with the actual app identifier, and add the corresponding Associated Domains entitlement.
3. Extend the parser to accept that exact trusted HTTPS host and path, then handle universal links as well as the existing custom scheme.
4. Make the landing page show the destination, an Open in Hero Dirt button, the actual App Store link, and an Apple Maps alternative. Ensure displayed names are escaped and coordinates validated.
5. Share that HTTPS link, and verify installed/uninstalled behavior on physical iPhones, including cold and warm launches, denied app-opening prompts, and return from the App Store.

No website has been published and no Associated Domains entitlement has been added without a verified host.
