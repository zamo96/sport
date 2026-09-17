# Similar players: card and grid presentation

## Request and scope

Add a grid mode to Similar players with an animated transition from the full card and back. Scope is the native iPhone app, inferred from the current native work while an optional platform clarification is pending. Keep the existing dark visual language and default to a full card.

## Product and technical contract

Product Analyst defined acceptance; Solution Architect froze the following contract before Mobile implementation. Mobile owns DiscoverView.swift; root owns this packet and build/runtime verification; independent QA reviews the stable result. Preserve pre-existing native changes, including the empty deck and activity feed.

- `users` remains the canonical ordered list from the existing repository. Display mode and selected player ID are local presentation state. Grid selection does not reorder or submit a swipe.
- The full card displays the selected ID if present, falling back to the first remaining player. Existing actions capture that player and remove by ID. Prevent repeated actions and switching while submission is in flight.
- Grid uses two columns with static images, name, sport/level and location. Avoid story timers and video players per tile.
- Animate between the active card and its tile; honor Reduce Motion. Keep refresh, empty states, tutorials and the existing profile/authentication flows.
- Backend, recommendation inputs, API contracts and database schema are unchanged.

## Acceptance and QA checklist

- Clearly labeled card/grid control with accessible selected state; card default.
- Both transition directions animate. Reduced Motion avoids spatial movement.
- Selecting a non-first tile opens that exact full card; profile, skip, like and block target it.
- Toggling preserves remaining players and their canonical order; refreshed selection falls back safely if removed.
- No duplicate swipe submission or late response removing an unrelated player.
- Grid hides swipe hints, never starts the swipe tutorial and preserves guest authentication gates.
- Empty/loading, one player, odd counts, missing photos, long names and larger text remain usable.
- Grid scrolling remains usable when switching back to a single card.

## Domain coverage

Affected: discover presentation and read-only display of profile, sport/level and location. Ranking/eligibility is unchanged. Availability/time slots, proposals and matches, search/lobby lifecycle, chat/unread, notifications/devices, cancellation/no-show/reliability and premium rules are unchanged. Existing swipe behavior is reused with ID-safe client selection; no domain rule changes.

## Required verification

Run Debug iPhone Simulator build and focused native interaction/visual checks, followed by independent QA. Web lint/test/build and Prisma generation do not apply to this native-only change. Record runtime gaps explicitly instead of claiming a pass.

## Results

- Implemented in `ios/TennisSearchIOS/Views/DiscoverView.swift`: labeled Card/Grid modes, static two-column tiles, matched geometry, selected-ID deck, exact-ID action removal, submission guards, scroll anchoring, Reduce Motion, and tutorial/account state handling. This packet is the only other file owned by the task. Pre-existing edits were preserved; comparison baseline was copied before implementation.
- Final Debug Simulator build: PASS. Command: `xcodebuild -project ios/TennisSearchIOS.xcodeproj -scheme TennisSearchIOS -configuration Debug -sdk iphonesimulator -destination 'platform=iOS Simulator,id=A48882FF-E21F-41FC-A8D4-577865B0A26E' -derivedDataPath /tmp/tennissearch-grid-derived CODE_SIGNING_ALLOWED=NO USE_MOCK_DATA=YES build`. Log: `/tmp/tennissearch-grid-build-final.log`. A final incremental build includes all implementation edits.
- Swift syntax parsing and scoped `git diff --check`: PASS. Independent QA compared the task diff with the pre-existing baseline and found no blocking regression. Static review covers canonical order, selected player identity, ID-based removal, duplicate submissions, late account/tab results, guest gates, tutorial mode conditions, image fallbacks, and accessibility.
- No native automated test target exists. Web lint/test/build and Prisma generation were not run because there are no web/backend/schema changes; native compile/type checks passed.
- Runtime attempt: created an isolated iPhone 17 Pro simulator, installed the mock build and seeded a local guest fixture. Simulator control returned stale Window-menu accessibility elements (`-10005`) and `Screenshot unavailable`; resetting the control session did not recover it. App launch also stalled. The task's stalled launch was canceled and its isolated simulator shut down; other simulators were preserved.
- **Moderate residual verification risk:** animation smoothness in both directions, deep-row lazy-grid scroll anchoring, large text, rapid toggles and guest/swipe interactions have static review only. Verify these on an iPhone or responsive simulator before release. No runtime pass is claimed.
- Existing overlapping discovery fetches and optimistic background dislikes were not redesigned. They may briefly restore stale candidates on refresh; the new action removal is ID-based and cannot remove an unrelated first card. No backend/API/database or ranking changes.

## Increment: map-linked grid, sports and full-card space

User asks to link the grid to a map, display by sport, and keep Card/Grid controls from obscuring the full card. Product Analyst and Solution Architect defined this increment before Mobile implementation.

### Frozen contract

- Integrate the mode control into the existing discover-tab row using compact, labeled-for-accessibility icons with 44pt targets. Remove its separate full-width content row. Keep the original navigation bar (Activity, search and authentication/notification controls); full-card photo and actions remain unobstructed. The selected Similar tab uses a short visible label with an icon fallback on narrow screens and retains its full accessible name.
- Grid mode shows a dark map above the two-column tiles, with All sports and available-sport chips. One sport-filtered ordered subset drives map, grid and the selected full card. Filters never reorder or remove canonical candidates and do not change server ranking. No sport chips consume space in full-card mode.
- Map points describe approximate areas from a supported city and matching primary district. If only a supported city is known, use its city center; otherwise do not invent a point. Do not use viewer coordinates as a player location. Unmapped players remain in the grid. No location permission or geocoding request is required.
- Group candidates sharing an area into a count marker. Selecting it highlights/scrolls the selected member or first ranked member; it does not apply another filter. Selecting a tile opens the existing full card. Returning preserves sport and selected player; map and tile highlight that selection.
- Filtered-empty state offers clearing the filter; only truly exhausted canonical candidates enter EmptyDeck. Missing/removed/blocked selections reconcile safely. Shared-sport players appear once and display the selected sport's level.
- Preserve submission locks, captured-ID actions, tutorials, Reduce Motion and the newer `selectedTabContent: AnyView` runtime-crash fix.

### Ownership and verification

Mobile owns native presentation and any required source registration; root owns this packet, builds and simulator checks. Independent QA reviews the stable diff. Affected domains are read-only profile, sport/level and approximate district presentation. No backend/API/schema, availability, ranking, gameplay lifecycle, chat, notifications, reliability or premium changes.

Acceptance: map/grid sport membership agrees; selecting grouped markers links to the correct tile; selecting a non-first tile and returning preserves identity/filter; no fabricated locations; full-card controls and bottom actions remain visible; empty filters/unknown locations and Reduce Motion work. Required checks: native Debug simulator build, focused runtime/visual checks and independent QA. Web/npm and Prisma checks remain inapplicable.

### Increment implementation and verification

- Mobile changed only DiscoverView.swift. Added shared sport filtering, conservative approximate-area resolution, grouped map markers and a map/grid presentation component. Canonical user order and the existing captured-ID swipe actions remain intact. Strict known-city aliases prevent ambiguous names such as Moscow, Idaho from being placed in Moscow, Russia. Unmapped users remain in the grid.
- The mode control is integrated into the existing tab row, not a new row. Runtime inspection showed that adding native toolbar mode controls made the navigation buttons unavailable to this Simulator accessibility session; the final layout restores the original native navigation bar and uses ordinary content buttons without consuming more vertical space.
- Pure helper verification: 26/26 PASS. A temporary harness executes the actual SimilarPlayersMapData source, actual SupportedCity/district-name resolution, and the centroid helper against fixture user models and sample district geometry. Covers sport membership/order, multi-sport deduplication, known/missing/foreign-city district resolution, strict city aliases, empty geometry, grouping order and unmapped candidates. Scripts: `/tmp/tennis-grid-qa-generate.py`, `/tmp/tennis-grid-qa.swift`. This is not a full catalog or SwiftUI integration test.
- The `selectedTabContent: AnyView` crash fix was compared with the increment baseline and is unchanged. Existing unrelated native edits were preserved.
- Preliminary native builds and independent static QA passed. Runtime on the isolated Grid QA simulator confirmed the full card and both action buttons fit above bottom navigation; normal skip advances Elena → Maria → Sofia, guest invitation opens authentication, and dismissal preserves the player. Final row-layout build and map interaction checks follow below.
- Final row-layout Debug Simulator build: PASS (`/tmp/tennissearch-map-grid-row-build.log`), using the same destination/derived data/mock override command above. Scoped whitespace: PASS. Independent final QA reviewed the final source and runtime evidence: PASS for implemented scope, with limitations below. No native XCTest target exists; web/npm/Prisma checks do not apply to this native-only increment.
- Final runtime on iPhone 17 Pro simulator: PASS for all original navigation buttons plus Card/Grid accessibility, full-card fit above bottom bar, switching to 3 tiles/3 approximate map markers, Padel filtering to Maria + level 4/10 + one Central marker, marker → selected tile, tile → full Maria card, and return preserving filter/selection. Skipping Maria produced the filtered-empty reset action; clearing it restored Elena, and the grid contained Elena/Sofia only, verifying non-first-player removal by ID. The actual exhausted-deck screen and guest auth/dismissal path also passed before the final row-only adjustment.
- **Map basemap limitation:** custom markers render and work, but Apple Maps road tiles remained grey in this simulator. GeoServices logs show missing map style resources and DNS error `NSURLErrorDomain -1003` for `configuration.ls.apple.com`. No network/VPN/security configuration was changed. Verify the base map on a device/network that can reach Apple Maps; do not interpret this as a successful road-map visual check.
- **Remaining manual checks:** larger Dynamic Type/narrow physical phones, the system Reduce Motion toggle, very long grids and animation frame quality. State transitions and identities were exercised; frame-by-frame animation quality is not claimed. The conservative city whitelist may omit unfamiliar spellings; such users remain in the grid.
- Changed areas: DiscoverView.swift and this task packet only for the increment. No backend, API, database, ranking or matching-input changes. The test simulator uses synthetic local mock data; real accounts and other simulators were not altered.

## Increment: native player annotations, pinned controls and Searches modes

User reports that pinch gestures beginning over players do not zoom the map, asks for person cards with sport details on the map, visible top controls on return from a full card, and the same compact Cards/Map switch in Searches.

### Frozen scope and ownership

- Native Map specialist owns new `DiscoverPlayersMap.swift` and its Xcode registration. Mobile Integration owns `DiscoverView.swift`. Architect independently reviews the contract and final QA. Root owns this packet and build/runtime evidence. Existing dirty edits are preserved; increment baseline is `/tmp/tennissearch-native-map-before.swift`.
- Replace SwiftUI annotation buttons with native MKMapView/MKAnnotationView. Marker content is noninteractive; MapKit owns pan, pinch and selection. Person markers show name, avatar/initials, sports and sport-specific level. Respect Reduce Motion. Preserve camera on selection/ordinary state updates.
- One item per player at the existing approximate district/city coordinate, without invented precise locations or jitter. Native clustering zooms spatial groups; coincident groups expose individual players through a picker. Unknown locations remain in the grid.
- Selected sport drives both map labels and grid membership; all-sports markers use compact multiple-sport presentation. Preserve canonical ranking, captured-ID actions, submission guards and the `AnyView` crash fix.
- Pin the existing tab/mode row below the normal navigation area, with an opaque background and space in the layout. Returning from a selected card must leave controls visible and preserve player/filter.
- Searches means the adjacent Discover Searches tab, not bottom My Searches management. Move its List/Map control into the same compact tab row, animate content changes and disable the outer tab-swipe gesture while its map is active. Preserve date/sport filters and existing search actions.

### Acceptance and domain coverage

Validate marker-origin gestures, individual and clustered selection, matching sport labels/levels, selection preservation, return scroll position, unobstructed card actions, Searches modes/filters/actions and map pan without tab changes. Native Debug build is mandatory; focused runtime and independent review follow the stable diff. Physical multi-touch and visual checks unavailable to automation must be identified explicitly.

Affected domains: read-only profile, sport/level, approximate geography and discover/search presentation. Availability/date filters and search/lobby actions retain existing behavior. No changes to backend/API/schema, ranking/eligibility, chat/unread, notifications/devices, cancellations/no-show/reliability or premium. Web/npm and Prisma checks are inapplicable to this native-only scope.

### Implementation and verification

- Native map file and four Xcode registrations added. Player annotation visuals use passive UIKit subviews with native MapKit selection and clustering. Stable IDs and coordinate signatures prevent metadata/selection updates from resetting the camera. Avatars load with downsampling, caching and reuse cancellation. The map never requests player/device coordinates; existing conservative approximate-area resolution is reused.
- Discover integration pins the single existing tab row, scrolls back to it on mode changes, retains the selected player and sport filter, and presents a picker for coincident players. Searches reuses the compact mode-control layout, transitions by opacity, and does not attach the parent tab-drag recognizer while its map is active. Existing actions, filters and AnyView boundary were preserved.
- Focused actual-source helper harness: 26/26 PASS after integration freeze. Native parser, Xcode project validity and scoped whitespace checks PASS. No native XCTest target exists; web/npm/Prisma checks are inapplicable.
- Initial complete Debug build PASS (`/tmp/tennissearch-native-player-map-build.log`). Runtime revealed emoji fallback glyphs could wrap sport/level labels; replaced marker emoji with compact plain text. Subsequent Debug build PASS (`/tmp/tennissearch-native-player-map-final-build.log`), with one- and two-sport labels visibly fitting. Cluster-fit edge spacing was then checked separately below.
- Runtime on isolated iPhone 17 Pro Grid QA simulator: full card and bottom actions fit; map/filter membership matches the grid; Padel selects only Maria; native annotation tap highlights Maria and scrolls to her tile; tile opens exact full Maria card; returning retains Maria/Padel and shows pinned controls. Native spatial-cluster tap zooms to separate Maria and Sofia. All-sports Maria marker shows both Tennis 4/10 and Padel 4/10.
- Searches runtime: compact Cards/Map controls visible; both mode directions work; date and sport filters remain; selecting a date with no results then returning to Cards preserves the empty filtered result; All dates restores Sofia. With geolocation denied in the isolated synthetic simulator, search marker and selected search card still render with the existing response action. No response was submitted and no real account was changed.
- Independent static QA of the stable integration/native bridge found no blocking issue. Final build and bounded visual corrections are recorded below before closure.
- Remaining verification limits: physical pinch/pan beginning on a marker cannot be reproduced with available simulator automation; coincident-player picker has static review but no same-coordinate runtime fixture; large Dynamic Type, narrow devices and animation frame quality need manual review. Apple Maps base tiles remain grey in this simulator (earlier GeoServices DNS/resource errors); marker rendering/selection works. Network/VPN/security settings were not modified.
- Final cluster-fit correction uses 56pt vertical margins and adaptive side margins. Final Debug build PASS (`/tmp/tennissearch-native-player-map-verified-build.log`); frozen source manifest `/tmp/tennissearch-native-player-map-verified.sha256` independently verified. Final runtime cluster tap separates Sofia/Maria, removes the cluster after animation and displays both complete marker cards within the map edges, including both sports and levels on Maria. Independent final QA: PASS with the manual limitations above.
- Final touched areas for this increment: `DiscoverView.swift`, new `DiscoverPlayersMap.swift`, four registrations in `TennisSearchIOS.xcodeproj/project.pbxproj`, and this task packet. Existing unrelated native edits are preserved. No backend, API, database or recommendation-input changes.
