# Centers map layout

## Request and scope

Use the main screen's compact List/Map switch in iOS Centers and keep the map clear of bottom navigation. Native presentation only. Existing working-tree changes must be preserved.

## Acceptance

- Two 44 pt icon targets matching Discover, with localized accessibility labels and selected traits.
- List remains default; search, sport, favorites and selection behavior survive mode switches.
- Map size follows the available safe area above navigation; selected-center actions and location control remain reachable.
- Verify compact and large layouts, keyboard, selected/empty results, filters, and navigation.

## Domain coverage

Sport filtering and geolocation/district presentation are affected only visually; no domain behavior changes. Profile, sport levels, availability, proposals, search/lobbies, ranking, chat/unread, notifications/push, cancellations/no-show/reliability, premium are unaffected. Web/backend/API/database contracts remain unchanged.

## Ownership and sequence

Product Analyst defines acceptance; Solution Architect reviews layout and safe-area ownership; Mobile implements CourtsView only; root builds and verifies; independent QA reviews final changes and limitations. ContentView owns navigation safe-area reservation. CourtsView consumes that available space without hardcoded duplication of tab-bar height.

## Technical design

Architect approved CourtsView-only changes. Place compact picker in header, split scrolling list from bounded map, allocate map from parent geometry, and clip the map to its bounds. Selected-card presentation must adapt to short space; no minimum map height may exceed the available region. Keep existing models, filter sources, map focus and action handlers. Search suggestions remain accessible while editing.

## Implementation

- CourtsView uses Discover-style 44 pt icon toggle in its title row, with Russian/English accessibility labels and selection traits.
- List and map have separate layouts. Map consumes parent safe-area geometry; search/filter controls scroll within a capped region. Removed fixed 520 pt map and duplicate 116 pt bottom padding.
- Selected center is below the map in a bounded card region; compact mode retains name, sport, Details and Find a game. Location control overlays the map.
- During search focus the selected card hides to avoid sub-44 pt action viewports; it returns after keyboard dismissal. Location padding adapts to short map height.
- Only CourtsView.swift and this packet belong to this task. Existing unrelated working-tree edits are preserved. No API/database/domain-rule changes.

## Checks and limitations

- Initial Debug Simulator build: PASS for arm64 and x86_64. Command: `xcodebuild -project ios/TennisSearchIOS.xcodeproj -scheme TennisSearchIOS -configuration Debug -sdk iphonesimulator -derivedDataPath /tmp/tennis-centers-layout/derived CODE_SIGNING_ALLOWED=NO USE_MOCK_DATA=YES build`. Log: `/tmp/tennis-centers-layout/build.log`.
- Final incremental build after keyboard correction: PASS, log `/tmp/tennis-centers-layout/build-final.log`.
- Scoped `git diff --check`: PASS. Independent QA found the compact-keyboard viewport issue; Mobile applied the correction above.
- npm lint/test/build and Prisma generation do not apply to this native-only change. No native unit/UI test target exists in the project.
- Runtime attempt: mock build installed on Design QA and Compact QA simulators; synthetic guest fixtures only, no real accounts. App launch succeeded and simulator framebuffer showed the main screen. CUA returned stale Window-menu elements (`-10005`), invalid element IDs, and unavailable screenshots; resetting and retrying did not recover interaction. No Centers runtime visual/interaction pass is claimed.
- Moderate residual verification risk: confirm compact/large device map bounds, map gestures, search/suggestions, keyboard, selected-center actions, empty results, filters and mode/tab round trips on a responsive simulator or iPhone before release. On short screens controls/card areas scroll separately; metadata beyond center name/sport is available in Details.
- Final independent code review: PASS after keyboard correction, no remaining portrait compact/large code blockers. Visual acceptance remains unverified; extreme landscape/split-view and Dynamic Type also require device review.

## Regression: selected club still overlaps navigation

User reported that the first fix did not remove overlap. Previous code/build review did not establish runtime acceptance. Preserve this history rather than treating the earlier pass as visual evidence.

Product acceptance remains: selected club card and both actions must sit fully above bottom navigation. Source review found that clipping against raw GeometryReader bounds does not protect content when those bounds still include the inherited navigation inset.

Architect approved a Centers-only structural change in ContentView: allocate screen and menu as vertical siblings, clip the navigation container to the actual remaining area, and skip the outer safe-area menu insertion for this branch. Other tabs retain their existing layout. Menu sizing remains owned by ContentView; no duplicated navigation-height padding in CourtsView. Decorative backgrounds do not participate in content sizing. Mobile owns these two files, root owns build/runtime and this packet, independent QA reviews final evidence.

Add a DEBUG-only mock-data launch shortcut for direct map preview with an existing synthetic guest fixture, without bypassing authentication or changing repository choice. This permits screenshot verification when external simulator interaction is unavailable. Domain/API/database scope remains unchanged. Regression verification pending.

### Regression implementation and checks

- ContentView now lays out the Centers navigation container and existing bottomBar as separate VStack children. The screen and its loading overlay are clipped to the allocated region. The outer safeAreaInset inserts the bar only for other tabs. No menu-size constants were duplicated.
- CourtsView's full-bleed gradient is now a background rather than a sizing ZStack child. Existing map/card sizing, filters, actions and keyboard handling remain intact.
- DEBUG + mock-data-only `-centers-map-preview` / `-centers-list-preview` flags set initial tab/mode for local inspection. They do not bypass ContentView authentication/guest checks and do not select a different repository.
- Build: PASS with `xcodebuild -project ios/TennisSearchIOS.xcodeproj -scheme TennisSearchIOS -configuration Debug -sdk iphonesimulator -destination 'platform=iOS Simulator,id=98428F04-B10D-4BDD-8C46-E4CAB6F5B252' -derivedDataPath /tmp/tennis-centers-layout/derived CODE_SIGNING_ALLOWED=NO USE_MOCK_DATA=YES ONLY_ACTIVE_ARCH=YES build`. Final log: `/tmp/tennis-centers-overlap/build-final.log`.
- Initial attempt failed because disk space was down to 147 MiB. Only task-owned generated build artifacts were removed; stopping this task's stalled simulators plus that cleanup restored 3.7 GiB. Rebuild then passed. No user documents or unrelated build artifacts were removed.
- Scoped diff whitespace check: PASS. Independent QA: structural code review PASS; screen/menu have separate allocation and other-tab behavior is preserved.
- Runtime visual acceptance remains BLOCKED: Compact QA, Design QA and a newly created clean Centers Regression QA simulator all eventually failed to boot with `launchd failed to respond` / `could not bind to session`, including attempts after space recovery. No screenshot of Centers/selected card was obtained, so no compact/large visual pass is claimed. Test devices ended shut down; the new disposable simulator was deleted and other active simulators were left untouched.
- Residual moderate verification risk: selected-card and action visibility still need a responsive simulator/device check, including compact/large layouts, keyboard dismissal and menu-mode transitions. The code/build checks establish the structural separation but do not substitute for that runtime check. Web/npm/Prisma checks are not applicable; existing native player-auto-advance tests target unrelated logic.
