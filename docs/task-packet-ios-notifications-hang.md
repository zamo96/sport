# iOS notifications entry hang — 2026-09-09

## Report and scope

User reports production iOS bell → notifications becomes unresponsive: cannot scroll or navigate back; restarting is required. Account identifier remains in the conversation rather than source documentation. Root owns orchestration/runtime checks, product_scope supplied acceptance, ios_architect supplied design then owned the isolated mobile patch, notification_qa independently reviews it. Preserve all pre-existing checkout changes.

## Acceptance

- Normal Home bell opens responsive notifications; back button and edge swipe work before/during/after refresh, including repeated visits and cancelled interactive pops.
- Scroll and group collapse/expansion work for 0, 1 and 30 mixed items (current backend cap is 30).
- Polling/realtime/refresh and network errors do not trap navigation or repeatedly recreate the destination.
- Existing links reach their destinations, notification badge clearing remains intact, and opening the screen does not mark chat messages read.

## Domains and contracts

Direct: iOS notification presentation and Discover source-screen lifecycle. Regression surfaces: chat unread/badges and notification destination routing. Unchanged: profile, sports/levels, geo/districts, availability, proposal/game-search lifecycle, matching/ranking, push-device registration, cancellation/no-show/reliability and premium. No backend/web/Android/schema/API or data-contract changes. NotificationManager/repository remain the source of notification data and seen semantics; presentation state is local to Discover.

## Evidence and design

The bell was an anonymous NavigationLink inside Discover's toolbar. Its existing source foreground gates remained true until onDisappear. This is a concrete lifecycle gap, not proof of the reported production hang's root cause. Earlier feed-entry captures implicated Discover layout, but previous early-pause fixes were insufficient on that route; do not present the new patch as verified production resolution.

Patch only `ios/TennisSearchIOS/Views/DiscoverView.swift`: explicit isNotificationsPresented state, root navigationDestination, cancel pending player auto-advance before push, and gate existing geometry/playback work while notifications are presented. Preserve mounted Discover identity, selection and destination handlers. Add bell accessibility label/identifier. No speculative notification list/manager rewrite; response count is bounded.

Pre-edit snapshot: `/tmp/tennissearch-notifications-discover-before.swift`.

## Diagnostics and verification

- Connected phone read-only metadata: Sportia 1.2 (2026090603), iOS 18.7.8. This identifies the connected installation, not a user-confirmed report version.
- Time Profiler could not attach to PID 13270 (process unavailable); no valid freeze capture obtained. Requested user to leave the actual hang open for capture. Did not install or launch on the physical phone.
- Native adjacent regressions: player auto-advance 39 assertions PASS; chat-receipt 29 assertions PASS. These are not UI responsiveness tests.
- Simulator Debug build and normal-route UI validation in progress.
- npm lint/test/build and Prisma generation are not applicable to this isolated Swift-only change; no web/backend/schema changes belong to this task.

## Status and risks

Candidate correction implemented; production resolution remains unverified. Simulator iOS 26.3.1 differs from connected iOS 18.7.8. Need real-device normal entry/scroll/back acceptance and ideally a before-fix hang stack. No production or TestFlight deployment performed.

## Final local validation

- Debug simulator build PASS, arm64 and x86_64: `xcodebuild -project ios/TennisSearchIOS.xcodeproj -scheme TennisSearchIOS -configuration Debug -sdk iphonesimulator -derivedDataPath /tmp/tennissearch-notifications-derived-20260909 CODE_SIGNING_ALLOWED=NO USE_MOCK_DATA=YES build`. Log `/tmp/tennissearch-notifications-build-20260909.log`.
- Scoped diff whitespace check PASS. Source hashes for DiscoverView, NotificationsView and NotificationManager still match the build-validation snapshot (`/tmp/tennissearch-notifications-source-hashes.json`).
- Dedicated simulator 71287633-1641-495D-95B7-EE361FAE52BB, iOS 26.3.1: installed candidate with UseMockData YES and used local mocked email login. No production account access.
- Normal Home → bell → notifications → back passed FIVE cycles via accessibility interaction. Collapsing and expanding New Messages group both PASS. Three mixed mock notification rows were present.
- CUA scroll action failed with `noWindowsAvailable`; scrolling, edge-swipe/cancelled pop, and precise coordinate hit-testing are NOT verified. 0/1/30 rows, delayed/offline refresh, notification destination taps and real-account seen behavior are NOT covered by this smoke check.
- Independent QA found no definite scoped-code regression. Native helper tests and build PASS; full production incident acceptance remains OPEN.
- Saved release 1.2 (2026090603) has identical NotificationsView and NotificationManager sources and the same anonymous bell NavigationLink before this fix.

This is a candidate lifecycle correction, not a confirmed resolution of the production hang. Follow-up: capture the actual unresponsive process while the user leaves notifications open, then validate on the affected iPhone before release. No TestFlight/App Store/backend changes were published.

## User-authorized release

User subsequently authorized release. Shipped the isolated candidate through TestFlight upload as1.2.1 (2026090901), based on latest0604 release; unrelated workspace changes excluded. Apple accepted upload2026-09-09 14:07:44 Moscow time and reported processing. Full fresh builds,159 frozen native assertions and independent distribution/source checks PASS; release details in `docs/release-2026090901.md`. No public App Store submission. Production hang resolution remains unconfirmed pending actual-device acceptance.
