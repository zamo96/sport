# Progressive player grouping as the map zooms

The user now explicitly requests grouping on the player map: a wider view shows groups and zooming reveals more individual cards. This supersedes only the no-clustering rule of `task-packet-schematic-district-player-cards.md`. The schematic positions within preferred districts, exact public anchor separation and map visibility policy stay unchanged.

Scope: iOS map presentation and focused native regression tests. Root owns coordination, builds/runtime validation and this packet; Architect owns requirements/design/independent QA; Mobile owns implementation. Preserve unrelated dirty sources. No backend, profile, ranking, permission or release change.

Acceptance:

- Nearby/colliding player cards form compact native MapKit groups at wide zoom. Zooming in splits those groups into smaller groups and individual cards; zooming out groups them again.
- Group counts represent unique players, not repeated district memberships. A group is a zoom action, never a district card, player picker or shortcut to an arbitrary player. Tapping an individual opens that player.
- Group activation centers its current schematic member positions and makes measurable zoom progress on every repeated tap until individual cards separate. It must not repeatedly refit the same padded bounds and get stuck.
- Preserve schematic layout, sport filtering, selection, native pan/pinch over passive annotation content, busy/stale-action guards, and camera neutrality on metadata/selection updates.
- Keep all memberships in the data; MapKit chooses the visible grouping. Selected players must not force overlapping cards into an otherwise grouped view.

Affected domains: discovery map presentation and sport-filtered counts. Unchanged: profile and geographic membership/persistence, availability, requests/searches, ranking formulas, chat, notifications, reliability and premium. Other clients and backend are outside scope.

Validation: focused actual-source grouping/count/zoom tests plus existing layout/privacy/auto-advance/onboarding regressions; native Debug simulator build and whitespace checks. Use the existing DEBUG-only twelve-player same-district fixture to inspect a wide group, repeated group taps revealing individual cards, direct player opening and preserved sport controls. Record any physical gesture or map-tile limitations explicitly. Web npm and Prisma checks are not relevant to this native-only change.

Implementation is limited to `DiscoverPlayersMap.swift`, `ios/Tests/PlayerMapTests.swift` and `ios/Tests/run-player-map-tests.sh`. Individual cards use native clustering with normal display priority, including the selected player. Groups use a compact circular UIKit image on a native annotation with an explicit hit area, required group-only visibility priority and unique-player count.

The initial standard MapKit marker exposed an accessibility group but did not paint its badge in this simulator. It was replaced before completion with the explicit UIKit badge, matching the application's existing cluster rendering approach. The count, membership and zoom helpers did not change with that rendering correction.

Final validation:

- Actual-source map checks: 84 assertions passed, alongside 39 auto-advance and 36 onboarding assertions (159 total).
- Debug arm64 iOS Simulator build passed with Xcode. All 61 tracked source/configuration/test input hashes were unchanged after the final build. Source whitespace checks passed.
- Runtime on the twelve-player same-district fixture: wide view showed one circle with 12; activation split it into groups of 8 and 2 plus individual cards; successive activations split a smaller group into pairs and the 05/06 pair into individual cards. Activating player 05 opened the correct full card (tennis level 3). Returning to grid showed the wide group and visible top controls. The tennis filter remained usable and retained 12 players because every fixture player plays tennis.
- Both groups and individual cards explicitly forward accessibility activation to the same guarded handlers as native physical selection. Weak captures, reuse reset and live membership resolution prevent stale actions. No custom touch recognizers or interactive child views were added.
- Independent architecture/QA source review passed for clustering, unique counts, camera behavior, privacy preservation and accessibility forwarding.

Evidence is in `.artifacts/player-map-zoom-clusters/`: final scoped patches against the task-start snapshot, test logs, `build-final.log` and `build-inputs-final.json`. The task-start snapshot is `/tmp/tennis-player-map-cluster-baseline`.

Limitations: physical pan/pinch, pinch starting on a card, zoom-out by gesture and large text need an on-device check. The computer-use service rejected coordinate gestures with `noWindowsAvailable`; accessibility activation was successfully verified instead. Simulator base map tiles did not load, so the verification covers card/group rendering and interaction but not map-tile appearance. Cards near the viewport boundary can be clipped by the native map edge after zooming. This is a local implementation, with no new TestFlight upload or backend deployment. The temporary stress fixture is disabled when the app is relaunched normally.
