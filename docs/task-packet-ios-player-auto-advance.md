# iOS player media auto-advance

## Request and ownership

After the white media progress completes, gracefully move the player card downward and show another player without requiring a swipe. Orchestrator owns this packet and integration verification; Product Analyst defines acceptance; Solution Architect freezes local state contracts; Mobile implements; independent QA reviews the stable diff. Preserve all pre-existing working-tree changes. Baselines are in `/tmp/tennis-auto-advance-baseline`.

## Product acceptance

- Scope: iOS Similar Players full-card deck. Finish the complete media sequence (existing 10 seconds per item, up to six), including the 10-second placeholder for a player without media.
- Passive completion defers the player behind unseen candidates and retains the ability to revisit and like. It sends no dislike, like, match, or notification request.
- Animate the outgoing card down and reveal the next card smoothly. Honor Reduce Motion.
- Pause progress when inactive, obscured, interacting, or during tutorials, loading and refresh. Resume without counting hidden time.
- Only the active player may advance, once per completion; protect manual swipe, account, filter, mode, navigation and asynchronous transition races.
- Handle zero/one player and exhausted unseen candidates without repeatedly dismissing the same player. Keep revisiting available.
- Grid/map, profile previews, incoming likes, explicit swipes and guest authentication retain their behavior.

## Domain coverage

Affected: discover presentation, media progression, and local viewed queue. Profiles, sport/level and location are displayed but their rules are unchanged. Server ranking/eligibility inputs, availability/time slots, proposals/matches, search/lobby lifecycle, chat/unread, notifications/devices, cancellations/no-show/reliability and premium gating are unchanged. No backend/API/database contract or schema changes.

## Verification plan

Run the Debug iOS Simulator build, focused executable native-state regression checks where feasible, and runtime UI checks in an isolated mock simulator. Independent QA reviews the final task diff against the saved baseline. Web lint/test/build and Prisma generation are not applicable unless implementation scope expands beyond iOS. Record unavailable checks and residual animation/device risks explicitly.

## Technical design and results

Architect approved a local presentation queue separate from repository `users`: unseen candidates first, then viewed FIFO. With at least two remaining players, continue cycling with full fresh media timers; with one, fill the bar and stay. Grid-selected identity takes precedence until retirement. Reset session state when account/location/sport scope changes; same-scope refresh retains viewed ordering. Tab and mode changes cancel pending transitions.

`SwipeCard` receives defaulted playback/completion inputs, preserving other usages. A monotonic active-time clock pauses without catch-up and resets on promotion. Parent owns queue, visible-screen/viewport and presentation gates, and cancellable ID/context-checked transition. Child owns touch and safety-menu pause. A defaulted safety presentation callback may be added in `UIComponents.swift`; other safety callers retain their existing UI. Completion cancellation must release its latch for retry.

Mobile owns implementation in those two files. QA owns focused test-only regression coverage and final independent review. Root owns simulator builds/runtime verification.

## Validation results

- Debug iOS Simulator build PASS for arm64 and x86_64: `xcodebuild -project ios/TennisSearchIOS.xcodeproj -scheme TennisSearchIOS -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/tennissearch-auto-advance-derived CODE_SIGNING_ALLOWED=NO USE_MOCK_DATA=YES build`. Log: `/tmp/tennissearch-auto-advance-build.log`. Existing unrelated ProfileView duration/sendability warnings also occur in the passing baseline build.
- `sh ios/Tests/run-player-auto-advance-tests.sh`: PASS, 27 assertions against the exact production Foundation helpers extracted from DiscoverView.swift. Tests cover full media duration, placeholders, six-item cap, paused elapsed time, completion freeze, shared looping, resets and viewed queue rotation/refresh/removal.
- Swift syntax checks and scoped `git diff --check`: PASS. QA static review against the saved baselines found no blocking issue; no passive completion path calls a swipe API or changes server ranking.
- Native test files: `ios/Tests/PlayerAutoAdvanceTests.swift` and `ios/Tests/run-player-auto-advance-tests.sh`. No XCTest target or project registration added. Verified source hashes: `/tmp/tennissearch-auto-advance-verified.sha256`.
- Web lint/test/build and Prisma generation are not applicable: no web/backend/schema edits in this task.
- Runtime verification is running on the isolated `TennisSearch Auto Advance QA` simulator, UUID `B17AEC90-4A48-4DCE-AE7C-E06EDA3A8877`, using mock data and a synthetic guest profile. No real account actions are performed.
- Runtime caught a visibility integration bug despite passing state tests: both viewport/deck preference values remained zero across the lazy content hierarchy, permanently pausing playback. Replaced ancestor preference propagation with direct GeometryReader onAppear/onChange state updates, clearing frames on disappearance. Temporary diagnostics were removed. QA re-reviewed the fix and the 27 state assertions still pass; final build/runtime verification follows.

## Final outcome

- Corrected final Debug build PASS for arm64 and x86_64; log `/tmp/tennissearch-auto-advance-final-build.log`. Current source hashes replace the earlier manifest at `/tmp/tennissearch-auto-advance-verified.sha256`. No diagnostic overlay or launch flag remains.
- Runtime PASS: media progress advances, Elena/Maria/Sofia rotate without input and previously viewed players reappear; no passive candidate count decrement. An open safety menu holds Elena for over 30 seconds, then playback resumes on dismissal. An open player profile holds Elena and the same partially filled bar for over 12 seconds, then resumes on dismissal.
- Runtime PASS: explicit skip reduces the remaining count from three to two and shows another player; grid retains both remaining players, choosing Maria opens Maria with fresh progress. A further explicit skip reduces the count to one. The final Maria card remains with a full bar after more than 20 seconds, without self-dismissal.
- Independent QA: PASS with the residual limitations below. The original visibility blocker is resolved and verified on the running app.
- Remaining moderate interaction-verification risk: physical drag/hold injection fails in the simulator controller (`noWindowsAvailable`), although accessibility-driven buttons, profile taps, safety popup and grid selection work. Real-device swipe/hold coexistence, animation frame pacing, Reduce Motion, large Dynamic Type and live multi-video playback were not manually exercised. Pure clock tests cover all media timing and pause semantics; reduced-motion and interaction gates received static review. Verify those physical-device cases before release.
- Viewed order is local to this Discover view/session and resets with account/location/sport scope; it is not a server-persisted viewing history. No API, schema, ranking inputs, eligibility, notification or premium behavior changed. Existing unrelated working-tree edits are preserved.

Final touched areas: `ios/TennisSearchIOS/Views/DiscoverView.swift`, `ios/TennisSearchIOS/Views/UIComponents.swift`, the two focused files in `ios/Tests`, and this task packet.

## Increment: visible viewed players and replay

User clarified that departing cards should accumulate visibly below the current card and be available for explicit revisiting. Add a labeled, compact horizontal «Просмотренные» strip below the deck, with photo/name buttons and newest viewed first. Use the existing local viewed queue as source of truth. Repeated viewings never duplicate players; current player may remain highlighted in history. Tapping returns that exact player to the full card with fresh media progress and scrolls to it. A single player's completed media should also appear in history without animating a self-dismissal. Explicit swipes/blocks remove unavailable players from history. Preserve scope resets, filters, auto-advance, pause and API behavior.

Orchestrator owns this packet/build/runtime checks; Product Analyst defined acceptance; Solution Architect freezes the view/selection contract; Mobile owns implementation; QA owns focused regression tests and independent review. Increment baselines: `/tmp/tennis-viewed-tray-baseline`.

Affected area remains native discovery presentation only; all server/domain/ranking/notification/premium rules remain unchanged. Run native build, existing plus focused regression assertions, and simulator accumulation/replay verification. Web/Prisma checks remain inapplicable.

### Increment implementation and validation

- `ViewedPlayerQueue.newestViewedIDs` projects unique history newest-first against current eligible players; successful explicit removals/block remove history IDs. No profile snapshots or server history added.
- Added a bounded horizontal lazy thumbnail tray after the deck, with count, replay hint and current-player outline. Replay selects exact ID, restarts media even for the current player, and requests scroll to the existing pinned-controls anchor. Replay availability intentionally does not require the main card to be in the viewport.
- Singleton media completion now records history while leaving the full card in place. Roster changes can retry a completed clock so new candidates still enter automatic rotation.
- Native production-state regression harness expanded to 39 assertions; QA reports PASS and no static blocker.
- First increment build hit host disk exhaustion (`No space left on device`). Standard Xcode clean of the old temporary nearby-build output succeeded; free space returned to approximately 4GB. Rebuilding with two build jobs; no source files were removed for cleanup.
- Final increment Debug Simulator build PASS for arm64/x86_64 with `-jobs 2`; log `/tmp/tennissearch-viewed-tray-final-build.log`. An additional standard clean of old activity-feed build output kept disk space available. Existing ProfileView warnings remain unrelated.
- Root independently reran the native helper harness: PASS, 39 assertions. Scoped diff whitespace checks pass. Simulator update initially stalled after disk exhaustion; the dedicated test device is being restarted for runtime verification.
- Runtime initially showed the tray below the fold behind the persistent bottom navigation. Added a compact, visible «Просмотренные · N ↓» button beside condensed swipe hints; it scrolls the existing list into view without modifying history or media. Final affordance build PASS on the arm64 iPhone Simulator: `/tmp/tennissearch-viewed-tray-affordance-build.log` (same build command with the dedicated simulator destination and `ONLY_ACTIVE_ARCH=YES`).
- Final runtime PASS on the dedicated mock iPhone: automatic playback accumulates three unique entries; newest-first thumbnails, names and current outline are visible above bottom navigation after tapping the new button; Russian hints/button fit on one row. Selecting Maria from the tray returns Maria's full card with a fresh timer and retains all three history entries. Earlier Sofia replay also passed. No default-size clipping or overlap in the revealed tray.
- Singleton/filter runtime PASS: selecting Padel resets history and yields only Maria; after full media duration, Maria stays visible and history becomes one entry. Selecting that current entry resets the full progress bar to a new partial bar, scrolls back to the main card, and leaves history count at one.
- Independent QA accepts the implementation with existing physical-device verification limits: coordinate drag/scroll injection reports `noWindowsAvailable`, while accessibility-driven navigation/replay works. Large Dynamic Type, Reduce Motion and real-device gesture/frame pacing were not manually exercised. History remains local to the current discovery session/context.
- Increment touched files: `ios/TennisSearchIOS/Views/DiscoverView.swift`, `ios/Tests/PlayerAutoAdvanceTests.swift`, and this packet. Verified source manifest: `/tmp/tennissearch-viewed-tray-verified.sha256`. All prior unrelated work and the existing auto-advance implementation are retained.
