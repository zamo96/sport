# iOS card-to-Viewed continuous flow — 2026-09-09

## User correction

User rejected the previous downward shrink/fade as unattractive and explicitly requested an engaging effect of flowing from one place into another. This supersedes the earlier conservative no-flight design. Required outcome: the same full player card visibly transforms and travels into a specific real Viewed thumbnail; it must not disappear and be replaced with an unrelated avatar.

## Ownership and design

Root: orchestration, runtime visual inspection/build/demo. motion_product: revised requirements. ios_architect: architecture and mobile implementation after root approval. product_scope: independent QA. Preserve all prior dirty edits, especially notification foreground/cancellation guards.

Approved approach: transform the actual existing outgoing SwipeCard instance using visual scale/offset/mask along a curved path, keeping its media instance paused and visible. Fade card details while the image remains identifiable, evolve card aspect/corners into a 46pt thumbnail, softly settle at the exact endpoint. Reveal next card below in parallel. Use one-time native marker measurements held in nonpublishing weak references; do not introduce layout-feedback state updates or duplicate/restart video.

A persistent compact Viewed dock provides a real, visible reserved landing slot above the tab bar, even before the first completion. It uses actual history and existing full-tray access. A full-tray destination may be used only if reliably visible; prefer one stable dock over fragile target switching. No automatic page scrolling. Ensure dock placement and clipping do not obscure the morph, card actions or bottom navigation.

## Acceptance and invariants

- Continuous visible identity from large card through flight to exact final miniature, with no disappearing gap, endpoint jump, duplicate avatar or clipped route.
- First completion has an already-visible slot; pending presentation does not mutate history. Repeat and two-player wrap retain unique newest-first history.
- Commit existing ViewedPlayerQueue exactly once on successful arrival. No passive like/dislike/network mutation; preserve full-media timing and ranking.
- Replay returns the selected player and restarts its media clock. Singleton records receipt while staying full-size; no fake flight away and back.
- Cancel safely on notifications/navigation, foreground/scene, context/filter/account, interaction, refresh, roster or viewport changes. Release any temporary scroll disable and restore full opacity/position without a stale pending destination.
- Reduce Motion uses a brief stationary fade/receipt, no flight/scale/bounce.
- Next player becomes interactive after arrival; no invisible overlay remains.

## Domains and verification

Affected: iOS discovery presentation and local history only. Profile/sport/location data are displayed unchanged. Backend, API/schema, ranking/eligibility, availability, proposals/search/lobby, chat/unread, notification/push semantics, cancellation/no-show/reliability and premium remain unchanged.

Run native regression harness and meaningful geometry/state tests if introduced, Debug iOS simulator build, and actual recordings inspecting early/middle/endpoint frames. Check first and repeated arrival, two-player wrap, replay, singleton and notification cancellation. Assess Reduce Motion and physical gesture/frame pacing where tooling allows; disclose missing coverage. Npm/Prisma checks do not apply to native-only scope. No release/upload requested in this iteration.

## Implementation and review

Implemented a measured 800ms curved morph of the existing live SwipeCard into the dock, blending its final cover before an atomic history handoff. `ViewedCardFlight` is a pure geometry helper. Native endpoint markers publish no geometry state; clipping is restored at commit/cancel/marker teardown. Dock buttons preserve replay and full history access.

Independent QA added finite/invalid geometry, overshoot, exact destination and source preservation cases to `ios/Tests/PlayerAutoAdvanceTests.swift` and the existing harness. 485 assertions pass. Static review passes cancellation, singleton, replay, source identity, same-window target and invalid-geometry safety. No backend/schema/API changes.

First full simulator build passed, but actual recording found a blocking visual issue: the nested safe-area inset placed the dock behind the bottom menu. `ContentView.swift` now uses the existing courts-style VStack(content, bottomBar) for Discover, providing real bounded space above the menu. Independent QA reviewed this small containment fix. The final rebuild and visual verification passed after the containment correction.

Pre-edit baselines: `/tmp/tennissearch-viewed-flow-before.swift`, `/tmp/tennissearch-viewed-flow-content-before.swift`. Frozen source: `/tmp/tennissearch-viewed-flow-source-20260909`; hashes `/tmp/tennissearch-viewed-flow-source-hashes.json`.

Status: local implementation complete; final build, native tests and scoped visual QA pass. Not deployed.

## Independent QA — final polish review

Static decision: PASS for `DiscoverView.swift`, the scoped `ContentView.swift` containment change, and the final presentation polish. The dock is opaque at rest and transparent only while the actual card travels across it. Both cards retain the same 800ms transition window. `SwipeCard.detailsOpacity` defaults to 1 for all other callers and fades only the active card's details during normal-motion flight; its media/background subtree remains mounted. Cancellation restores details through the existing exit-state reset, and Reduce Motion retains its stationary fade path.

Independent checks after these final changes: `ios/Tests/run-player-auto-advance-tests.sh` PASS (485 assertions); Swift syntax parsing PASS for both changed views. Native tests cover existing media clocks and local history plus exact source/destination geometry, finite positive morph samples, bounded progress, and invalid source/target rejection. The tests exposed an invalid-rectangle guard gap that was corrected before the frozen build.

Root's corrected-containment simulator evidence confirms that the dock is visible above the bottom menu, the card lands at its measured thumbnail, first and repeated arrivals preserve unique history through counts 0→1→2→3, notifications push/back works, and Discover→Matches→Discover remains responsive. These runtime results were reported by root; QA independently reviewed the source and test outputs. The first build's hidden dock is resolved in this evidence.

Final polished-build visual confirmation: PASS. QA independently inspected `/tmp/tennissearch-viewed-flow-polished-strip.png`: continuous outgoing surface, receding details, exact avatar endpoint above the bar, count commits on arrival, next card revealed below, no sampled clipping/gap/ghost. Runtime recording uses mock players with fallback initials, not actual uploaded media.

Root additionally verified on the final build: first and repeated arrivals through 3 unique viewed players; opening full history (card actions remain reachable after the automatic history scroll); replay of Maria confirmed by current-player accessibility state; notifications push/back; cards→grid→cards; two-player Sofia→Maria advance with history count remaining 2; singleton Maria stays full-size with one history item after another playback interval. Discover→Matches→Discover was verified after the final containment fix; subsequent polish did not change that container.

Final build: Debug arm64 iOS simulator PASS (`ONLY_ACTIVE_ARCH=YES ARCHS=arm64`, mock repository, code signing disabled). Initial pre-containment version also passed arm64+x86_64 build. Log `/tmp/tennissearch-viewed-flow-build-20260909.log`; native harness `/tmp/tennissearch-viewed-flow-tests-20260909.log` 485 PASS. All 99 frozen iOS source-file hashes match the workspace. Npm lint/test/build and Prisma generation are not relevant to this native-only diff. Touched modules: DiscoverView.swift; ContentView.swift; PlayerAutoAdvanceTests.swift and its runner; this task packet.

Demo: `.artifacts/ios-viewed-card-motion/flow-preview.mp4`, 2.5 seconds, actual simulator speed. Full evidence: `/tmp/tennissearch-viewed-flow-polished-20260909.mp4`, `/tmp/tennissearch-viewed-flow-edgecases-20260909.mp4`.

Residual risks: medium — physical iOS 18 gesture/frame pacing and original production account not exercised; actual uploaded-photo/video handoff not visually exercised; exact mid-flight cancellation, Reduce Motion, rotation/small-screen/Dynamic Type runtime not exercised (their guards/fallbacks reviewed statically). Coordinate gesture automation returned `noWindowsAvailable`, so manual scroll/edge-swipe cannot be claimed; accessibility button navigation and automatic history scrolling worked. These cases should be checked on device before another release. No production deployment or account verification is implied by this QA decision.


## Follow-up: remove duplicate Viewed dock

User clarified that the existing Viewed list below the card is sufficient. Remove the entire separate bottom dock and its navigation button; retarget the continuous morph to the actual newest avatar in that existing list. No vertical auto-scroll or replacement/pinned destination. Prepare a pending in-list first slot before measuring, including 0→1, without committing history. Offscreen destinations may clip naturally at the viewport boundary; missing geometry must fall back briefly and still advance once. Preserve replay, queue semantics, cancellation, singleton and Reduce Motion. Scope is native presentation only; other domains/contracts unchanged.

Ownership: root orchestrates/reviews/builds, motion_product requirements, ios_architect design/mobile, product_scope independent QA. Previous motion/verification above describes the superseded dock version.

Implementation: removed the dock, navigation button, unused tray-scroll request, dock safe-area inset, and exact ContentView containment workaround. Existing viewedPlayersTray prepares a unique pending first slot, uses the actual 46pt avatar marker (validated against player ID), and commits history only after arrival. Four bounded 20ms preparation attempts validate token/context/player/readiness before and after waits. Missing geometry uses a 180ms crossfade and still advances once. No vertical page scrolling or native clipping changes; below-fold trajectories naturally clip. Arrival emphasis now belongs to the real list entry.

Independent static QA PASS; 485 native assertions and both Swift syntax checks PASS. Source baselines `/tmp/tennissearch-viewed-tray-only-discover-before.swift`, `/tmp/tennissearch-viewed-tray-only-content-before.swift`. Frozen iOS snapshot uses `/tmp/tennissearch-viewed-flow-source-20260909`; current correction manifest `/tmp/tennissearch-viewed-tray-only-source-hashes.json`. Final build/runtime pending.

Parallel workspace task owns notification navigation/toolbar and refresh-observer investigation. Its edits are preserved and are outside this correction. No claim that the production notification hang is resolved.


Tray-only runtime follow-up: first clean build PASS and native485 PASS. UI verified removal of the separate dock/button, 0→1→2→3 unique history, replay of Maria, and notifications/back in the local mock. Video `/tmp/tennissearch-viewed-tray-only-20260909.mp4` then exposed repeated fallback fades instead of flight. A temporary instrumented frozen copy (never workspace) showed first native target capture success followed by repeated missing destinations. The user-keyed ForEach around the first avatar recreated its native marker below the fold. Mobile replaced it with a stable structural first slot (`if let first`) and kept lazy per-user identities for the remaining history. Independent QA approved this fix; repeated-flight runtime verification pending. Temporary auto-entry/logging fixture exists only under /tmp and must be removed from the final build snapshot.


### Tray-only final verification

PASS: clean Debug arm64 simulator build `/tmp/tennissearch-viewed-tray-stable-slot-final-build.log`; native regression harness485 PASS `/tmp/tennissearch-viewed-tray-stable-slot-final-tests.log`; syntax/diff checks PASS. All99 frozen source hashes matched the workspace at final verification (`/tmp/tennissearch-viewed-tray-stable-slot-final-source-hashes.json`). Temporary capture prints and mock auto-entry are absent from both workspace and final snapshot. Native-only scope; npm/Prisma checks not applicable.

Three consecutive successful captures after the stable-slot fix used the same actual46pt destination. Independent QA inspected `/tmp/tennissearch-viewed-tray-stable-strip.png`: repeated Maria→Sofia morph now occurs, outgoing surface moves toward the actual below-card list, no duplicate dock/button, count1→2 commits after arrival. This resolves the earlier fallback-only failure. Video `/tmp/tennissearch-viewed-tray-stable-20260909.mp4` used temporary mock auto-entry/capture logging only; app motion code matches the final clean version. Short evidence `.artifacts/ios-viewed-card-motion/tray-flow-preview.mp4`. Earlier normal-login clean run verified first/repeated history, Maria replay and notifications/back; the subsequent fix changed only stable identity of the first tray slot.

Residual risk (medium): fully visible landing, horizontal history dragging, precise mid-flight cancellation, Reduce Motion, physical iOS18 frame pacing/gestures, and real uploaded-photo/video continuity remain unverified. The filmed destination is below the viewport, so only the path toward it and measured endpoint are established; this follows the accepted below-fold behavior. CUA coordinate scrolling repeatedly returned noWindowsAvailable, although accessibility-button navigation worked. Production notification hang is investigated separately and is not claimed resolved. No new deployment.

Final scope completed: separate Viewed dock/button removed, prior dock-only ContentView layout restored, existing Viewed tray is the sole destination and replay surface. Product files touched: DiscoverView.swift and ContentView.swift; existing native test files unchanged in this correction. Final task packet updated.
