# Nearby discovery for an empty city

Date: 2026-09-06. Status: implemented and verified in the workspace.

## User intent and scope

When the selected city has no eligible players, automatically offer the nearest eligible players and clubs by radius, with honest location and distance. The current working tree contains substantial earlier changes; preserve them. Do not deploy, seed or mutate profiles/databases as part of this implementation.

Product Analyst reviewed current empty states. Solution Architect located strict city/place barriers in discovery and court filtering. Backend and Matching have one owner; Web and iOS have separate owners after contract freeze. Root owns this packet, integration, mandatory checks and independent final QA; the QA planning agent subsequently implements iOS due to the four-agent limit and does not perform its own final acceptance.

## Frozen contract

- Existing nonempty local results remain unchanged. Fallback only applies when the corresponding eligible local result is empty.
- Player scope: primary/default/swipe discovery, authenticated and guest. Likes, upcoming, existing matches and hot/regular search tabs retain their meaning and do not gain arbitrary people.
- Court scope: selected city/sport and empty-deck suggestions; club fallback is independent of player fallback.
- Shared server policy: radius stages 25, 50, 100, 200 km, first populated stage independently for each entity. At most 12 fallback players and 6 fallback clubs. A user-specified smaller radius is expanded visibly when empty; expansion never runs beyond 200 km. No unbounded worldwide results.
- Preserve sport, level, gender, format, surface, availability, account status, verification, onboarding, self/block/swipe/match exclusions and applicable court constraints. Only geography may expand.
- Center: canonical selected place coordinates; same-city profile coordinates where appropriate. An explicit different city must not use the old home origin. Unknown/invalid coordinates cannot qualify as nearby; zero coordinates are valid. Distance is straight-line, not travel distance.
- Keep array return types and existing JSON envelopes. Add optional `nearby: { originCity: string; radiusKm: number; distanceKm: number }` to fallback player/court previews and empty-deck court summaries. Empty-deck court summaries also include `city`. Local rows omit or null the metadata.
- Clients render a clear nearby heading, radius, city and straight-line distance. They must not reimplement eligibility or reapply the original geographic constraint to hide the returned fallback.
- `/courts` accepts arbitrary trimmed city (previous two-city enum is insufficient), optional canonical `locationPlaceId`, and existing `sport`. `/discover/empty-state` accepts city/place/sport context and supports guest recommendations without private invite data.
- Counts/summaries for primary discovery use consistent server selection without creating impression records. Existing safety checks for notifications remain in place.
- No Prisma schema changes. Optional response fields are backward compatible for older clients.

## Ownership

- Backend/Matching: shared nearby policy, scoring eligibility opt-in, discovery orchestration and summaries, court service, serializers, query validation/API routes, meaningful regression tests.
- Web: discovery and guest UI, club UI, empty-deck summaries, request context and localized text. Remove hardcoded default-city fetching on the authenticated clubs page.
- iOS: optional Codable fields, API query context, nearby presentation and independent club suggestions, cache invalidation. Preserve all earlier native work.
- Root: documents, integration-only glue if needed, test/build execution and final review against acceptance.

## Acceptance checklist

1. Existing local eligible players/clubs retain their IDs, ordering and normal presentation.
2. Empty local selection returns the closest valid eligible objects within the first populated radius; ordering is nearest first with stable ties.
3. A nearby club does not suppress a farther eligible player, and fallback players do not hide nearby clubs.
4. Non-geographic conditions and safety exclusions hold in fallback.
5. Missing/invalid coordinates, no results within 200 km and backend failures have honest distinct handling; never substitute a default-city result as nearby.
6. Explicit selected city/place and same-name different places use the correct origin. Profile data is unchanged.
7. Web/authenticated/guest/iOS show the actual location and an explicit expanded radius, without claiming absence of all city users when filters caused the empty result.
8. Changing city, sport, filters or account cannot retain stale nearby content.
9. Likes/upcoming/hot/regular tabs and existing gameplay state transitions do not change.
10. Club selection sends the selected sport to the server so local clubs of another sport cannot suppress fallback.

## Domain coverage

Affected: geography/radius, discovery ranking and eligibility, player/club presentation, guest/auth context, discovery count alignment used by notification candidate checks. Profile records, sport-level definitions, availability rules, proposal/search/lobby lifecycle, chat/unread, push-device registration, cancellation/no-show/reliability and premium rules remain unchanged. No database migration.

## Validation plan and risks

Run targeted unit/service/route regression tests, then `npm run lint`, `npm run test`, `npm run build` (includes Prisma client generation), and Debug iOS simulator `xcodebuild`. Review changed UI and API flow where the environment permits; record runtime gaps rather than claiming unobserved behavior.

Risks to review: nearby metadata propagation through manually built previews; wrong-origin geocoding for an explicit city; client-side radius/district filtering suppressing expanded results; stale native supplementary caches; same-name city ambiguity; notification preflight semantics; performance of candidate/court fallback pools; preservation of unrelated worktree changes.

The 200 km cap and stage sizes are an initial product choice, not a claim about willingness to travel. Geographic expansion can surface less convenient candidates and may still return nothing in sparsely served regions. Later tuning should use real response/game data.

## Delivery and checks

- Backend/Matching: added `src/lib/nearby.ts` and `src/server/nearby-location.ts`; updated `src/lib/scoring.ts`, `src/lib/validators.ts`, `src/server/discover.ts`, `src/server/app-data.ts`, `src/server/serializers.ts`, and `src/app/discover/empty-state/route.ts`. The existing `/courts` handler consumes the extended query schema without needing a handler change. Canonical identity is accepted by primary discovery as well as courts. Safe player preview predicates apply to fallback club cards.
- Web: updated `src/app/discover/page.tsx`, `src/app/play/courts/page.tsx`, `src/components/discover/{empty-deck,swipe-deck,guest-discover-screen}.tsx`, `src/components/courts/courts-browser.tsx`, `src/lib/i18n/web/{discover,courts}.ts`; added `src/components/discover/nearby-notice.tsx`. Nearby clubs remain visible with player results. Guest club loading has independent retry and ignores obsolete responses.
- iOS: updated `Core/AppModels.swift`, `Services/{TennisRepository,APIClient,MockRepository}.swift`, `Views/{DiscoverView,EmptyDeckView,CourtsView}.swift` under `ios/TennisSearchIOS`. Removed the local-catalog coverage gate for club fetching; selected sports reach the server; optional metadata decodes old/new responses; loading context includes account, canonical place, city, profile sports, selected sport and profile radius. Unscoped club detail updates preserve existing nearby metadata from the current result.
- Root integration review found and fixed the guest iOS all-sports case: `/discover/empty-state` now receives the draft's sports as a comma-separated list when no single sport is selected. Root also guarded obsolete discovery-related responses before assigning account-specific upcoming data. A Swift compiler expression-complexity failure in the updated cache key was resolved by splitting the expression into typed intermediate values; final build passes.
- Added `tests/nearby.test.ts`, `tests/nearby-discover.test.ts`, `tests/nearby-courts.test.ts`, and `tests/nearby-empty-state-route.test.ts`: 35 new checks for stage/cap boundaries, invalid/zero coordinates, distance-first ordering, preserved non-geographic filters and safety predicates, existing local results, guest/auth contracts, independent sport radii, same-name distant places, summary/impression behavior, and guest invitation isolation.

Final verification:

- `npm run lint`: PASS, no ESLint warnings or errors. Log: `/tmp/tennissearch-nearby-lint.log`.
- `npm run test`: PASS, **70 files / 467 tests**, including all 35 nearby checks. Log: `/tmp/tennissearch-nearby-tests-final.log`.
- `npm run build`: PASS, including Prisma client generation and Next.js type checks, from an isolated snapshot with source/config hashes verified against the working tree. Log: `/tmp/tennissearch-nearby-web-build-isolated-final.log`. The initial in-place build collided with the running development server's `.next` artifacts; the isolated retry avoids that shared output. The first isolated attempt omitted the Tailwind configuration; copying the exact existing configuration resolved that setup error. No production source change was needed for these build-environment issues.
- `xcodebuild -project ios/TennisSearchIOS.xcodeproj -scheme TennisSearchIOS -configuration Debug -sdk iphonesimulator -derivedDataPath /tmp/tennissearch-nearby-derived CODE_SIGNING_ALLOWED=NO build`: PASS after final integration changes. Log: `/tmp/tennissearch-nearby-ios-verified-final.log`.
- Swift extracted-model Codable check: PASS for legacy/no-metadata and nearby responses, guest `invite: null`, authenticated invitations and metadata roundtrip; harness `/tmp/tennissearch-nearby-codable-check.swift`. It uses actual model declarations with unrelated types stubbed and is not a UI runtime test.
- Scoped/full whitespace check: PASS. Root independent integration review: PASS with the residual limitations below.
- Actual local browser: guest profile → ordinary nonempty primary discovery, then `/discover?distanceKm=1` → explicit 25 km fallback, first active player at 1.7 km, and independent six-club row at 1.4–2.6 km. No interest, messages or invitations were sent. This verifies the empty-radius transition; the empty-city/cross-city combinations are covered by service tests rather than claimed as observed real-user behavior.

## Residual limitations and rollout

- This change is in the workspace. No production deployment, TestFlight upload, profile update or database migration was performed.
- Native nearby presentation has a successful simulator build and model/contract checks; the full guest empty-city flow on a physical iPhone remains a manual check before release. The pre-existing player map supports approximate locations for recognized cities; players in other cities remain visible in the cards/grid without fabricated map pins.
- Courts currently store city text and coordinates rather than a canonical place foreign key. The selected-place origin and geographic cap reject distant same-name-city results, but do not represent municipal boundaries. Distance is straight-line and does not account for roads, water or border crossings.
- A missing/unresolvable origin or no eligible objects within 200 km legitimately remains empty. The first populated radius can have few results; it is not expanded further just to fill all 12/6 slots. Club suggestions are grouped by selected sport, with up to six fallback clubs per sport section.
- The existing discovery query loads the eligible player pool before geographic scoring. Court fallback adds latitude bounds and an exact distance cap, but large-catalog load/latency has not been benchmarked in this task.
- Matching impact: local scoring inputs and ordering stay unchanged; empty primary discovery may now admit other cities by measured distance. Fallback orders distance first, existing compatibility score for ties. Possible false positives are inconvenient travel despite geometric proximity; possible false negatives are missing coordinates and the 200 km cap. No premium or reliability weighting was added.
