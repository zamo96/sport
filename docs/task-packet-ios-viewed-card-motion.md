# iOS viewed-card motion — 2026-09-09

## Request and ownership

User asks for a more beautiful, smooth, pleasant transition when the automatically completed player card enters Viewed. Root owns orchestration, runtime recordings and builds; motion_product defined acceptance; ios_architect defines design then owns Mobile implementation; product_scope serves as independent QA. Preserve all pre-existing checkout changes, particularly the notification foreground gate just released. This request authorizes local implementation and verification; no new upload requested in this turn.

## Product acceptance

- A restrained approximately 540ms departure: outgoing card gently compresses downward, retains opacity initially, fades late; next card simultaneously settles into place without a blank flash.
- Successful retirement visibly acknowledges arrival in Viewed even when the tray is below the fold. No automatic scroll or change to deck layout dimensions.
- Completed active player enters history once, newest-first. Passive progression sends no like/dislike/network mutation. Existing full-media timing and ordering remain.
- Preserve replay with fresh progress, explicit swipe/profile actions, and pause/cancel behavior for notification navigation, mode/tab/filter/account changes, background, interaction, refresh and roster changes.
- Singleton records history while remaining visible; empty candidate handling unchanged.
- Reduce Motion uses a brief fade/accent without travel/scale.

## Architecture and scope

Source of truth remains ViewedPlayerQueue plus the existing cancellable token/context guarded auto-advance task. Visual phases are local Discover state. Use existing transforms and opacity, no continuously measured destination geometry, snapshot/media flight, blur, rotation or new matched-geometry coupling. Maintain existing mounted identity and foreground gates. Outgoing normal phase about360ms then late fade180ms; underlying next card moves concurrently. Queue commits only after state revalidation. A brief success-only accent on Viewed should not hold interaction disabled.

Touched product surface: `ios/TennisSearchIOS/Views/DiscoverView.swift`. Domains affected only native discovery presentation/media progression/local history. Profile/sport/location content unchanged. Backend, ranking/eligibility, availability, proposals/matches/search/lobby, chat unread, notification/push semantics, reliability and premium unchanged. No contracts/schema migrations.

## Verification

Native state regression harness plus Xcode Debug simulator build. Record at least two normal auto transitions and inspect intermediate frames; replay from Viewed; verify notification navigation and fully interactive restored card. Review Reduce Motion/cancellation branches and exercise when tooling supports it. Npm/Prisma checks are not applicable unless scope expands. Physical frame pacing/gesture constraints must be disclosed if not tested.

Status: design approved, implementation in progress. Baseline movie `/tmp/tennissearch-viewed-motion-before-20260909.mp4`; pre-edit source snapshot provided by Mobile.

## Implementation and static verification

Mobile changed only DiscoverView.swift. Normal departure has360ms initial compression then180ms late fade, each guarded after await. Underlay settles concurrently, and active subtree handoff uses identity transition. Queue commits exactly once. Viewed pill receives a separately cancellable mint accent; thumbnail insertion is subtle. Reduced-motion underlay stays at final scale/position throughout180ms crossfade. Cancellation clears both departure phases and arrival accent. Existing clocks, queue and notification foreground gates are preserved.

Baseline source `/tmp/tennissearch-viewed-motion-discover-before.swift`; scoped patch `/tmp/tennissearch-viewed-motion-scoped.patch`. Independent static QA and Swift syntax checks PASS;39 native state assertions PASS. Frozen native snapshot `/tmp/tennissearch-viewed-motion-source-20260909` has99 files with manifest `/tmp/tennissearch-viewed-motion-source-hashes.json`. Debug simulator build in progress at `/tmp/tennissearch-viewed-motion-build-20260909.log`.

## Final validation and deliverable

- Debug iOS Simulator build PASS for arm64 and x86_64, exit 0; log `/tmp/tennissearch-viewed-motion-build-20260909.log`. Built frozen current native sources with mock data; no source changes were made after the build. Existing ProfileView warnings are unrelated.
- Native actual-source state harness PASS: 39 assertions; log `/tmp/tennissearch-viewed-motion-tests-20260909.log`. Snapshot integrity 99/99 and current Discover source match confirmed. Scoped diff whitespace PASS.
- Runtime iOS 26.3.1 mock simulator: repeated three-player and two-player auto transitions recorded. Inspected initial/late/completed frames: outgoing card remains readable while shrinking/downward, next card fills its position, no blank intermediate card or returning foreground ghost. Successful Viewed pill accent is visible. Two-player recording includes transitions near 7.41, 18.18, 28.88, 39.61 and 50.29 seconds.
- Viewed replay PASS: Maria selected by identity, full card opens with fresh partial media bar and history count preserved. Notifications push/group collapse/back PASS; returned full card is visible and playback continues.
- Singleton PASS: Maria stays visible with a full media bar and exactly one Viewed entry after more than 20 seconds; replaying that entry restarts the bar and retains one entry.
- CUA coordinate scroll still fails with `noWindowsAvailable`, including after raising the simulator window. Physical scrolling/gestures, device frame pacing, runtime Reduce Motion, and cancellation timed precisely inside the 540 ms animation remain unverified. Code branches received independent review. No new geometry reader was introduced.
- Independent QA accepts this local motion change with these limits. No API, schema, ranking, notification semantics or production account changes. No TestFlight upload in this task.

Short real-time simulator preview: `.artifacts/ios-viewed-card-motion/transition-preview.mp4` (2.77 seconds). Full recordings: `/tmp/tennissearch-viewed-motion-after-20260909.mp4` and `/tmp/tennissearch-viewed-motion-two-players-20260909.mp4`.

Final touched files: `ios/TennisSearchIOS/Views/DiscoverView.swift`, this task packet, and the preview video artifact.
