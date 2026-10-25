# Trail sharing

## Current v1 behavior

More → Share Trail opens the standard iOS share sheet with two items:

1. The generated condition image as an actual image attachment.
2. The download URL: `https://apps.apple.com/app/id6770195112`.

The image includes the trail name, estimated condition, outlook, recent rain, and sharing time. No trail deep link, Apple Maps link, or long explanatory text is added to the outgoing share. The image itself carries the estimate disclaimer. The download link uses the assigned Apple ID; recipients can download once the App Store listing is public.

There is no upload, hosted sharing page, or Cloudflare service in v1. The app does not send messages itself; the person sharing chooses the recipient/app and completes the action in the system share sheet.

Previously distributed `herodirt://trail?...` links remain accepted, including Apple place-ID and coordinate/name forms. Their existing asynchronous resolution and error handling remain available for compatibility, but v1 no longer generates them from Share Trail.

## Deferred v2

The user tested Link Presentation metadata on a physical iPhone: the condition card appeared in the composer but delivered as a bare custom-scheme URL. That experiment is not the shipping v1 approach. Actual image attachments avoid relying on the survival of a link preview.

Universal HTTPS links, app/store routing, public preview metadata/images, and optional dated snapshots are deferred until the product needs them. The detailed [Cloudflare v2 plan](cloudflare-deep-links-v2-plan.md) covers the API contract, parallel Cloudflare/iOS workstreams, storage/privacy choices, deployment, device tests, and rollback. No Cloudflare resources have been provisioned and no Associated Domains entitlement has been added.
