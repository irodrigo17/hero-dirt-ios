# Nearby MTB recommendations — implementation plan

Status: plan only, following the user's October 24, 2026 clarification. Do not implement generic park recommendations. The goal is a short list of excellent, popular mountain-bike rides, not every nearby place that contains a trail.

## Data-source decision

Trailforks is the first integration candidate, conditional on approval and suitable fields. Its [official API page](https://www.trailforks.com/about/api/) requires approved access and app credentials; detailed documentation requires login. Its [data policy](https://www.trailforks.com/about/data/) requires approved API access and attribution, and excludes hidden tracks. Public [metadata documentation](https://www.trailforks.com/about/metadata/) distinguishes MTB activity from hiking, e-bike, and other activities. Verify the actual API response fields after approval rather than coding against unofficial endpoint lists.

MTB Project remains a candidate, especially for curated complete rides. I could not verify a current supported public API from its [historical data endpoint](https://www.mtbproject.com/data). Confirm supported partner access, current endpoints, permitted redistribution, cache limits, attribution, and ranking signals directly before selecting it. Do not assume old API keys or community wrappers still work.

Do not scrape either site or turn exported GPX files into an unapproved catalogue. Do not use Apple Maps parks as a substitute. If neither provider grants suitable access, leave recommendations unavailable and retain normal place search until a licensed MTB-specific source is selected.

## Recommendation unit and hard filters

Prefer a complete recommended ride or a recognised riding area to tiny connector segments. Each result needs a stable provider ID, canonical provider URL, MTB access, usable trailhead/entrance coordinates, difficulty, length, rating and rating count when available, and a current access/closure state. Keep provider-reported facts separate from Hero Dirt's weather-derived conditions.

Require MTB use to be explicitly supported. Exclude hiking-only, road-only, private/restricted, hidden, known closed, and unsanctioned routes. Don't infer bike permission from a generic park label. Where access is uncertain, omit the route from recommendations instead of describing it as a top MTB ride. Treat e-bike permission independently from ordinary MTB permission.

Deduplicate overlapping versions of the same ride and limit results from one trail system, so five near-identical segments cannot occupy the whole list.

## Ranking proposal

Build an initial candidate set within 25 km; expand to 50 km only when too few suitable rides exist and make that radius visible. These are proposed defaults, not implemented limits.

Rank eligible rides using:

- Quality: a rating adjusted for review count, rather than a lone five-star review outranking a consistently good ride with many reviews.
- Popularity: provider-supported recent rides/visits, or rating/review count if usage statistics are unavailable. Never fabricate usage counts or compare raw counts from different providers as equivalent.
- Distance: a modest preference for nearby trailheads, not a closest-first sort.
- Data confidence: complete, recent access information and a usable start point.

Start with quality and popularity carrying most of the weight. Tune weights against real examples after seeing the approved dataset. Display the reason for a recommendation (for example, "Highly rated · 240 reviews"), and use "Popular nearby" only when a genuine popularity signal exists.

Weather-derived conditions are an additional overlay, not proof that a trail is officially open. Fetch conditions only for the displayed shortlist to avoid a burst of weather and soil calls.

## App flow

In the empty state, offer "Find MTB rides nearby." Obtain the normal location permission at that deliberate action, with a manual town/region search alternative. The user has not approved sending location to a recommendation provider yet. Confirm the chosen provider and payload before implementation; prefer a coarse search region over retaining a precise location history.

Show three to five suggestions with name, difficulty, distance/length, rating and sample size when available, provider attribution, and an "Open in Trailforks/MTB Project" link. Opening a suggestion uses its trailhead for Hero Dirt conditions and offers the existing Save action. Store provider identity and source URL with a saved recommendation so provenance survives a later rename.

If access is denied, results are empty, the provider is unavailable, or no legal MTB rides qualify, keep the search and map actions available. Do not fill the space with generic parks or invent popularity rankings.

## Service boundary and credentials

Introduce a provider-neutral `MTBRecommendationsProviding` seam with fake data for previews and tests. Normalized results should explicitly represent missing ratings, counts, and access facts. Preserve provider IDs separately from local Place UUIDs.

If the approved API requires an app secret, keep it on a small backend/proxy rather than embedding it in the iOS binary. Cache public metadata by coarse region only within provider-approved limits; keep closures fresher than general metadata. Avoid logging precise user locations. The backend and vendor agreement are prerequisites, not infrastructure created by this plan.

## Delivery and acceptance

1. Confirm API access, terms and actual fields with one provider. No vendor outreach has been sent.
2. Validate a small dataset in known MTB areas: popular real rides rank well, generic parks and hiking-only routes do not appear, closures are respected, and segments deduplicate.
3. Implement the service adapter, normalization, cache and fake provider.
4. Test hard filters, review-confidence ranking, missing data, overlapping routes, denial, empty results, outages and request cancellation.
5. Add the empty-state shortlist, provider links and saving. Verify on simulator with fixtures and on-device with an approved live dataset.
6. Review attribution, current access data and ranking quality before enabling it broadly.

No production recommendation UI, API calls, credentials, or location-sharing changes are included in the current development branch.
