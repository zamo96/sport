# Player cards directly on the discovery map

## Request and scope

The user clarified that the map must show player cards rather than district cards. The deployed backend already publishes safe `mapAreas`; this task changes the iOS discovery presentation only. It does not require another backend deployment or schema migration.

Root owns orchestration, verification and this packet. Architect completed product/design review before dispatch and owns independent final QA. Mobile specialist owns `DiscoverView.swift`, `DiscoverPlayersMap.swift` and focused native regression tests. Existing dirty/concurrent work must remain intact.

Affected domains: player identity presentation, sport/level display and filtering, preferred-area map presentation. Unchanged: profile settings/persistence, geographic eligibility, ranking/recommendations, availability, requests/proposals, searches/lobbies, chats, notifications, reliability/cancellations and premium. Web/backend/Android are outside this correction.

## Frozen design and acceptance

1. Create a stable annotation for each unique `(userID, areaID)` membership from the existing filtered, map-visible candidate pool. Use valid server `mapAreas` only; preserve exact shared centers, without GPS, geocoding or invented coordinate offsets.
2. Individual cards show the actual player's photo/initials, name, sports and sport-specific level. Area names provide secondary context. Tapping opens that player's full card using canonical user ID.
3. Coincident/overlapping annotations must still show player identity. A cluster uses the first uniquely ranked player's card plus the count of other unique players. Multiple memberships of one player never inflate the count. A single unique player opens directly; a multi-player cluster opens an ordered player picker, whose rows show photo/name/sport and open the selected player.
4. Remove obsolete area selection/sheets so an invisible area filter cannot narrow the visible player pool. The list beneath the map remains unique users in existing rank order.
5. Sports filter updates cards and clusters together. Opted-out, invalid-area and old-payload users remain excluded from the map while ordinary recommendation-card eligibility stays unchanged.
6. MapKit retains pan/pinch, including gestures beginning on annotation cards. No embedded buttons or competing gesture recognizers in annotation content. Revalidate asynchronous selections against current items and busy state.
7. Preserve card/map animation, player selection on round trips, pinned controls and existing swipe/auto-advance guards. Metadata updates and selection should not reset the camera.

## Validation plan

- Focused native tests exercise actual extracted production helpers for membership identity/deduplication, sport/visibility/area filtering, cluster user uniqueness/order and stale selection handling.
- Run existing native player auto-advance and required-onboarding regression suites.
- Run Debug simulator `xcodebuild` for the changed native surface.
- Use the existing mock simulator to inspect player/cluster cards, open a player and return, change sport, and pan from a card. Explicitly record any gesture/device checks unavailable through UI tooling.
- Web lint/test/build and Prisma generation are not required for this native-only correction; no web/backend/schema files are edited.

## Status

Implemented in four files: `DiscoverView.swift`, `DiscoverPlayersMap.swift`, `ios/Tests/PlayerMapTests.swift` and `ios/Tests/run-player-map-tests.sh`. The first two files were compared against task-start copies at `/tmp/tennis-player-card-map-baseline`; scoped patches are retained in `.artifacts/player-cards-map/`. No backend, model, project configuration or other client source changed in this task.

Validation completed:

- Actual production model/projection/selection helpers: **30 assertions PASS**.
- Existing player auto-advance suite: **39 assertions PASS**; required onboarding suite: **36 assertions PASS**.
- Debug arm64 simulator build: **PASS**, including an incremental final build after the card-fit padding adjustment. Logs: `/tmp/tennis-player-cards-map-build.log` and `/tmp/tennis-player-cards-map-build-final.log`. All **60 native source/config inputs** match the final build manifest. Mock data was enabled only by the build invocation; the installed simulator bundle was checked before launch.
- Swift parsing and scoped whitespace checks: **PASS**; repository `git diff --check`: **PASS**.
- Simulator UI: the overview shows Elena's actual player identity/sport/level with `+2`, not a district card. One tap opens three unique player rows in ranking order. Choosing Maria opens Maria's full card; immediate return highlights her memberships in both districts. The controls remain at the top and do not cover the card.
- Simulator native double-tap zoom separates geographically distinct memberships until an individual Sofia card is visible. Tapping it opens Sofia directly. Tennis-filter selection survives card/map round trips; the focused tests separately verify exclusion of nonmatching sports.
- An initial apparent tap failure was an accessibility snapshot timing issue: repeat single-tap screenshots showed the picker opening correctly. No speculative gesture changes were made.

Independent architect/QA final verdict: **PASS**, with the device/UI limitations below explicitly retained. Source ownership, build identity, tests and completed runtime flows were reviewed.

## Remaining limits and delivery

- Real pan/pinch, especially a two-finger pinch beginning on a card, still needs a physical-device check. The computer-use drag operation did not produce a reliable drag in either the map or an ordinary scroll surface, so no pan success or regression is claimed. Native MapKit recognizers remain enabled and annotation subviews remain passive.
- Map tiles were unavailable in this simulator both before and after the change; card rendering, selection and native zoom were observable on the map grid. Mock avatars used initials, so production photo loading was not visually verified. The existing image loader and fallback remain in use.
- Normal text size was visually checked. Very large accessibility text and narrow device layouts need a device check; the implementation expands annotation metrics and map fit padding.
- No new TestFlight upload or production deployment was performed. This is an iOS UI update requiring a new app build for testers; the already-deployed backend contract supports it without changes.
