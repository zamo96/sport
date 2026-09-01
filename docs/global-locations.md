# Global locations backend

The application stores a server-validated `GeoPlace` and uses its stable ID for user discovery, game-search snapshots, and notification isolation. Existing Saint Petersburg, Moscow, and Kazan strings are backfilled to built-in legacy places; only Saint Petersburg and Moscow have active service coverage.

## Built-in city catalog

Country lists and explicit city searches are backed by `world-cities-json@1.0.1`, a packaged snapshot of the SimpleMaps Basic World Cities Database. The catalog gives every displayed country an immediately available city list without a network request. With a blank query, the API returns the country's largest cities by population; active service areas (Saint Petersburg and Moscow) are pinned first. Submitted searches rank exact and prefix matches before population and query the external provider only when the packaged catalog has no match.

Catalog rows are not bulk-imported. Only places actually returned to a client are upserted into `GeoPlace`, with `provider = simplemaps` and the dataset row ID as `providerPlaceId`. The three historic Russian places are reconciled to their legacy IDs so releases and reverse-geocoding do not create duplicates.

The dataset is licensed under CC BY 4.0 and requires attribution to SimpleMaps. Both location endpoints include attribution metadata; clients should expose it in the location picker or legal notices. See `docs/third-party-assets.md`.

Russian catalog rows use a compact, generated SimpleMaps-ID-to-Russian-name map derived from the GeoNames RU country dump and Russian-language alternate names (CC BY 4.0). The SimpleMaps ID remains the persisted identity, while the original `city` and `city_ascii` values remain searchable aliases. This makes both `Новосибирск` and `Novosibirsk` resolve to the same place and prevents a locale change from changing `GeoPlace.id`.

This is an incremental packaged-catalog rollout. If future requirements need broader alternate-language names, regularly refreshed geopolitical data, or a public data ingestion pipeline, migrate the catalog adapter to GeoNames while preserving the existing `GeoPlace` IDs or maintaining an explicit alias table.

## Provider requirement

`GET /locations/cities` supports a blank query for the initial city list. Non-empty searches remain explicit submitted searches, not type-ahead or autocomplete calls. Clients must submit non-empty queries only after at least two characters.

Development can use the public Nominatim endpoint at its aggregate limit of one request per second. The adapter sends an identifying User-Agent, applies a global in-process throttle, caches successful responses for six hours, and has a 4.5-second timeout. This is not sufficient for a horizontally scaled production deployment and the public Nominatim service does not permit client autocomplete.

Production therefore requires `LOCATION_PROVIDER_URL` pointing to a commercial or self-hosted Nominatim-compatible endpoint. Without it, worldwide provider calls are disabled and only the built-in legacy-city fallback is returned. `LOCATION_PROVIDER_USER_AGENT` should identify the application and a monitored contact address. Provider attribution must be shown by the client according to the selected provider's terms.

The provider is replaceable through `src/server/locations.ts`; clients never send trusted city names or coordinates to the profile endpoint. They select a place returned and persisted by the backend, then submit its ID to `PATCH /me`.

## Deployment order

1. Apply `prisma/deploy/20260831_global_locations.sql`. The script is transactional and safe to run again: schema objects are guarded and data backfills are idempotent. The coordinate backfill only fills users whose `homeLat` or `homeLng` is empty, so precise coordinates captured from geolocation are preserved.
2. Apply `prisma/deploy/20260831_user_locale_override.sql` to add the validated account language override.
3. Configure the production provider variables.
4. Deploy the backend.
5. Release clients that send `locationPlaceId` and locale preferences; older clients can continue sending Saint Petersburg or Moscow in `city`.

The deploy SQL is a one-shot, transactional release script, consistent with the repository's dated additive deploy scripts. Do not rerun it after a successful commit: PostgreSQL type, table, index, and foreign-key creation is intentionally strict so a partially mismatched schema fails instead of being silently accepted. A failed execution rolls back as a whole and can be retried after the cause is fixed.
