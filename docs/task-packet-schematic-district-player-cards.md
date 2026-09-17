# Schematic individual player cards by preferred district

## Clarified intent

The user clarified that individual player cards should be distributed by their preferred districts, without positioning them at a personal location. This supersedes the exact-center clustering design in `task-packet-player-cards-on-map.md`: no district card, representative card, `+N` aggregate or player-picker intermediary should replace the individual cards.

The backend's existing `mapAreas` remains the only source of area membership. This is an iOS presentation change, with no production deployment, schema change, profile-coordinate change or new server query needed.

Root owns scope, task packet, builds and runtime verification. Architect owns product/design review and independent final QA. Mobile owns implementation in the discovery/map files and focused native tests; an explicitly gated mock-only stress fixture may be added for verification. Preserve unrelated dirty workspace changes.

## Design and acceptance

- Every eligible `(userID, areaID)` membership produces its own actual player card. The same player appears in each permitted district. Cards show name, photo/initials, sport and level, and directly open the canonical player's full card.
- Preserve the public area center separately from the schematic display position. Never consult or write private home coordinates, device location or location permissions. No synthetic positions enter API/profile data.
- Spread cards using deterministic map-space slots inside the existing public district polygon when its city and area match. For cities/areas without a matching shape, use a compact schematic grid around the shared public center. Describe the placement as schematic, not an exact location or authoritative district boundary.
- Use stable user IDs for layout, independent of recommendation ordering and metadata. Compute slots from the available candidate pool before local sport filtering. Do not add an unfiltered backend request to maintain positions. A genuinely changed server candidate pool may cause a new layout; local filter/selection changes should preserve it where the underlying pool is unchanged.
- Remove annotation clustering and its picker, keep every annotation individually available, and increase the map height to approximately 400 points. Dense city overviews can require zooming and panning; twelve people sharing one district must not collapse into one card and must be individually reachable at district zoom.
- MapKit retains native interaction over passive annotation subviews. Preserve pinned controls, card/map transitions, player selection, canonical actions and busy-state guards.
- Keep map opt-out, invalid-area filtering, sport filtering and unique below-map player counts. Existing ranking/eligibility and saved district policy remain unchanged.

Affected domains: discovery presentation, sport/level display and preferred-area schematic layout. Unchanged: user profile persistence, geographic membership, availability, requests/proposals, searches/lobbies, ranking formulas, chat, notifications, reliability/cancellations and premium. Other clients and backend are outside scope.

## Validation

Run actual-source native layout/projection tests for distinct slots, polygon containment/city guards, fallback, membership deduplication, exact-anchor separation, rank/metadata/local-filter stability, twelve co-located users and many all-city memberships. Run existing auto-advance and onboarding regressions, parser/whitespace checks and Debug simulator build. Inspect individual cards/direct opening, sports and card/map round trips in the simulator, including a twelve-player stress fixture. Record unsupported physical pinch/pan and real-map/photo checks explicitly. Web npm checks and Prisma generation are not relevant unless the implementation scope changes.

## Status

Implemented in five files: `ios/TennisSearchIOS/Views/DiscoverView.swift`, `ios/TennisSearchIOS/Views/DiscoverPlayersMap.swift`, `ios/TennisSearchIOS/Services/MockRepository.swift`, `ios/Tests/PlayerMapTests.swift` and `ios/Tests/run-player-map-tests.sh`.

The map uses stable, distinct interior slots from matching public district shapes, with city and actual point-in-polygon anchor guards. Unknown shapes use a compact public-center grid; polar/dateline cases preserve distinct valid positions. The exact public anchor is retained separately. Layout uses the available `users` pool before local filtering; no fetch site changed. Native clustering and the picker were removed, and map height is now 400 points.

Validation:

- Actual-source native map suite: **45 assertions PASS**, including 12 distinct interior positions, 216 district memberships, ordering/filter stability, city/anchor/concave-outline guards, fallback and privacy decoding.
- Existing auto-advance **39 assertions PASS** and required onboarding **36 assertions PASS**: **120 checks total**.
- Debug arm64 simulator build: **PASS**. All **61 native source/config inputs** match the successful build. Swift parsing and scoped/repository whitespace checks passed. Evidence is retained in `.artifacts/schematic-player-cards/`; baseline product files are in `/tmp/tennis-district-card-layout-baseline`.
- Normal simulator UI showed four individual memberships across three districts, including Maria in two areas. Activating her Moscow-area annotation opened her full player card directly. Header controls remained visible.
- The explicit DEBUG MockRepository flag `-district-player-cards-stress` produced 12 separate player annotations in one district, without aggregates or a picker. Accessibility activation of the extreme-position player 12 opened that player's full card; returning retained all 12 map annotations. Tennis filtering was selected and all 12 tennis players remained available. The fixture is off by default, initializes once per repository instance and does not exist in Release compilation.

Independent architect/QA verdict: **PASS with the manual limitations below**. Source, build identity, tests and observed normal/stress flows were reviewed; no blocking source defect was found. The final sport check and restoration of the normal fixture completed without further code changes.

## Remaining limits and delivery

- Dense overviews visibly overlap. Slots are distinct in map space so native zoom can separate them; this does not promise every card is readable at city overview.
- Physical touch reachability of distant cards after zoom, pan and pinch still need a device check. Coordinate-based computer-use calls failed with `noWindowsAvailable` despite working accessibility actions and screenshots. Re-selecting/raising the simulator did not resolve the tool failure. Accessibility activation confirms the player action, not touch-target reachability; no successful gesture test is claimed for this version.
- Normal text size and initials fallback were observed. Large text, real profile-photo loading and map-tile display still require device verification; this simulator's base map tiles were unavailable before these changes as well.
- The simulator was relaunched without the stress flag after verification. No new TestFlight build was uploaded and no backend/production change was made for this correction.
