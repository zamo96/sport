# Voluntary player visibility by preferred play area

Default policy update: the user subsequently requested default-on registration and a one-time enablement of existing accounts. See `task-packet-map-default-on.md`; it supersedes the default-off portions below, which describe the original implementation and validation.

## User intent

Players should appear in every district they chose as convenient for play. If no districts were chosen, appear in all districts of that city. Cities without district coverage use city-level placement. The user explicitly confirmed a separate **Show me on the map** setting, enabled by the player, default off.

This is a map of preferred play areas, not current position or residence. Showing a broader area does not itself anonymize a named profile or certify legal compliance. Legal consent wording/recipient scope remains a separate professional review consideration.

## Workflow and scope

Product/Architect froze requirements and contracts before dispatch. Implementation is isolated in `/tmp/tennis-district-player-map` on `codex/district-player-map`, copied from the current working tree including earlier completed nearby/analytics/native work. Baseline content/hashes are preserved in `.district-map-baseline.zip`/`.json`. Root integrates only this task's changes with guarded comparisons, preserving concurrent work.

- Backend/Web specialist: privacy setting and migration, update/read contracts, public map projection, nested user serialization, web profile control, backend tests.
- Mobile specialist: native models/API/profile control, area-based map and area-card filtering, native fixtures/helper tests.
- Architect/QA: independent acceptance review and regression planning, final review after checks.
- Root: integration, mandatory checks and this packet.

## Frozen API and policy

- `User.showOnMap` is boolean, database default false. Existing accounts remain opted out. Missing profile update field preserves stored setting; explicit false revokes it.
- Public `mapAreas` is an array of `{ id, cityId, cityName, kind: 'district' | 'city', districtId: string | null, label, latitude, longitude }`. It is empty unless the user explicitly opted in. Missing arrays on older servers mean no map eligibility in the new client.
- The backend alone computes area membership from `preferredDistricts`, canonical place coverage and the district catalogue. Coordinates are published district/city centers, never private `homeLat/homeLng` or live GPS.
- Valid selected districts yield membership in each selected district, deduplicated in catalogue order. A genuinely empty list yields all available city districts, regardless of legacy primary `district`.
- Mixed invalid/valid IDs retain only valid same-city IDs. A nonempty wholly invalid/foreign-city list yields no areas, rather than silently broadening visibility.
- Missing/null district preferences fail closed for cities with district coverage. An older profile PATCH omitting preferences preserves the saved selection before schema defaults; only an explicit empty array selects the whole city. Saving an opted-in profile with wholly incompatible preferences requires correction or explicit clearing. Cities without district coverage ignore stale preferences and use the city area.
- No district catalogue/coverage: one canonical city area. Unknown city identity/center: no invented marker. Nearby candidates remain in their own city's areas.
- Existing candidate eligibility, exclusions, ranking, radius and nearby fallback stay unchanged. Membership operates on the currently eligible returned candidates, not an exhaustive city directory.
- Public nested user serialization must not return private user records. Clean game-search partner/responder and match-other-user projections without changing gameplay transport fields.

## Native/web behavior

- Signed-in profile offers the voluntary toggle with clear text describing other players seeing the profile in chosen districts, or the whole city when no district is chosen. Existing profile save flow persists it; failed saves remain visibly failed.
- Area markers identify a district/city and unique player count, with visual player/sport context where practical. Selecting an area displays its player cards in existing recommendation order. All-areas reset restores the eligible map pool.
- Sport filtering updates areas, counts and cards together. Each user belongs to all selected areas but appears once within one area; actions use canonical user IDs.
- Map movement never changes filtering. Native pan/pinch remains owned by MapKit, including touches over annotation content. Selection does not reset the camera.
- Full card round trips retain sport and area selection. Preserve pinned opaque controls, the AnyView runtime fix, report galleries, nearby notices and existing swipe action guards.
- A selected area stays selected if a sport change or refreshed candidates leave it empty. The empty state offers reset and ordinary cards; it does not silently broaden the selection.
- Opted-out players remain eligible for ordinary recommendation cards; they do not appear in the area map/list. Guests cannot enable a persistent profile preference without authentication.

## Domains and acceptance

Affected: profile privacy setting, preferred play geography, discovery map presentation, safe public user serialization. Sports/levels are filtered/displayed with existing values. Recommendation ranking and eligibility, availability, game/search lifecycle, chat behavior, notifications, reliability and premium are unchanged.

Verify default-off migration and old-client omission; explicit opt-in/revocation; every selected district; empty preferences/all districts; invalid and cross-city IDs; unsupported/canonical cities; deduplicated area/card counts; sports and selection changes; no private fields in nested public payloads; old API/model decoding; preservation of existing flows and concurrent source changes.

Run targeted backend/native checks, `npm run lint`, `npm run test`, `npm run build`, `npm run prisma:generate` and native Debug simulator build. Database migration must be prepared and validated without touching production. Record any unavailable visual/device checks explicitly.

## Risks and delivery status

Implementation integrated into the main working directory with a baseline-guarded, task-only copy of 24 files. No conflicts or unrelated source changes were overwritten. Database and production remain unchanged; no TestFlight upload was performed for this feature.

Changed modules: native models/API/mock fixtures/profile/discover/map; Prisma User; `/me` and match payloads; candidate projections and serializers; web profile settings/translations; shared map-area and preference helpers; three regression test files; SQL rollout and this packet. The `src/lib/scoring.ts` change only carries the privacy flag in its input type; ranking inputs/formulas and eligibility did not change.

Validation on the integrated source:

- `npm run prisma:generate`: PASS; generated client only, no database mutation.
- `npm run lint`: PASS, no warnings/errors (`/tmp/district-map-lint.log`).
- `npm run test`: PASS, 506 tests / 73 files (`/tmp/district-map-tests.log`), including 39 new map/privacy/profile regression tests and existing nearby tests. The final `/me` guard rejects malformed raw district values, including comma-only input that the legacy parser would otherwise turn into an empty list.
- `npm run build`: PASS (`/tmp/district-map-build.log`).
- Native Debug simulator build: PASS (`/tmp/district-map-ios-build.log`); all 37 native source/config files compared are identical between the isolated build and integrated tree.
- Independent extracted-native-helper checks: 40/40 PASS (`/tmp/district-map-native-helper-qa.log`), covering decoding defaults, map eligibility, area validation, deduplication, sports and retained empty selection. These are helper tests, not device interaction tests.
- PostgreSQL 16 migration checks: 7/7 PASS in a temporary network-isolated container with a synthetic User table; tested defaults, opt-in, idempotence, NOT NULL, preservation and revocation. Container removed. Final SQL SHA256 matches the tested file: `d2633d0f8547e0d048ae0602f0bfb4eff9be3bf231430f194e5c1109a69ac259`.
- `git diff --check`: PASS.

Independent final QA verdict: PASS with the manual and rollout limitations below. The raw-preference widening issue found during review was corrected, then lint, the full test suite and production build were rerun successfully. No remaining blocking source defects were identified.

Residual risks and release requirements:

- Simulator UI automation returned CUA timeout `-10005` twice. Pinch starting on markers, visual control placement, profile-save interaction and card/map round trips still require a hands-on simulator/device check. No visual verification is claimed.
- Already distributed iOS 1.1.1 derives old map placement from public city/district data and does not understand `showOnMap`/`mapAreas`. The opt-in governs the updated map; it cannot prevent old clients from drawing old-style locations or revoke cached/public city data. If enforcement across all installed clients is required, release coordination and an explicit minimum-version strategy are follow-up work.
- Existing numeric player distance fields remain a separate possible inference channel. This feature does not eliminate all location inference or certify legal compliance.
- Area membership includes the currently returned eligible recommendation pool, not every account in a city. District catalogues are approximate. Current district coverage includes Saint Petersburg and Moscow; Kazan currently uses city coverage despite existing shape data.
- Default off means existing users must actively enable visibility. Apply the additive SQL before deploying the new backend, then distribute the updated client. See `deploy/migrations/20260906-player-map-visibility.md`. No automatic release is part of this request.
