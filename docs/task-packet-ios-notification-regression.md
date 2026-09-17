# iOS notification hang and toolbar bounds — 2026-09-09

## Scope and acceptance

User reports notification entry still hangs and bell/search icons extend past the screen. Orchestrator owns diagnostics and full app verification; Product Analyst/Solution Architect defines scope then implements as Mobile specialist; independent QA owns observer lifecycle verification and final review.

Acceptance: fully bounded 44-point toolbar controls and badges on compact screens; repeated notification entry/back remains responsive; scrolling/group toggles work; hidden Discover does not publish refresh-observer state; returning preserves pull-to-refresh. Notification list, routing, seen semantics, chat unread and existing campaign behavior remain unchanged. Real-device hang resolution requires actual reproduction, not merely a successful build.

## Design and boundaries

Concrete toolbar defect: existing badges offset beyond the measured control bounds. Concrete lifecycle risk: `RefreshProgressObserver.updateUIView` can synchronously write SwiftUI state and repeats zero-value writes; queued scroll callbacks are not suspended while Discover is hidden.

Patch only Discover's refresh observer call, observer helper, toolbar controls and toolbar label helpers. Bound badges inside 44-point controls; suspend/detach observer while inactive, invalidate on dismantle, coalesce asynchronous work and publish only changed finite values. Keep mounted Discover identity and existing notification presentation.

Another active task owns viewed-card flight/tray changes and ContentView's bottom-bar experiment. File ownership coordinated; no whole-file replacement or changes to those sections.

## Domains

Direct change: iOS notifications entry and toolbar layout. Regression surfaces: source-screen refresh and media lifecycle, notification badges/navigation. No backend/web/Android/schema, profile, sport/level, geolocation, availability, request/lobby, ranking, reliability or premium changes.

## Baseline evidence

Connected iPhone15 reports Sportia 1.2.1 (2026090901), iOS18.7.8. Process appeared in device inventory but Time Profiler could not find that PID; no valid freeze capture yet. User asked to leave the actual hang open for capture. Previous candidate release did not conclusively establish the production root cause.

## Verification plan

Build native app, isolate source snapshot from concurrent edits, run meaningful observer lifecycle checks, and use a dedicated compact simulator for notification navigation/scroll and toolbar inspection. No new source-mirroring tests. npm/Prisma checks do not apply to Swift-only work. No production or TestFlight release requested in this turn.

## Implemented and build validation

- Mobile specialist completed only the scoped Discover toolbar and observer blocks. Existing notification destination and NotificationManager remain unchanged.
- Exact working-source Debug simulator build PASS for arm64/x86_64 with `CODE_SIGNING_ALLOWED=NO USE_MOCK_DATA=YES`; log `/tmp/tennis-notification-regression-build.log`. 105-file snapshot hashes remained unchanged through build.
- Adjacent actual-source checks PASS: 485 player auto-advance assertions and 29 chat receipt assertions.
- Independent scoped code review PASS: no actionable new regression found. Observer lifecycle runtime and full toolbar UI checks are separate from source review.
- Isolated mock fixture build PASS, log `/tmp/tennis-notification-fixture-build.log`. Fixture changes are outside product sources: mocked automatic login, configurable 0/1/30 notifications, subsequent fetch delay/offline, large badge and accessibility type. Actual Discover/NotificationsView/NotificationManager sources are preserved. Artifacts under `.artifacts/notification-regression/`.
- Dedicated compact simulator: iPhone13mini, 375-point width, iOS26.3.1, `9F6DA58F-7A8E-48C9-8297-D24D20CF14AC`. Simulator startup/install is slow; UI acceptance pending.

## Final verification limits

- The other coordinated task reported a successful normal notification push/back on its already-working mock simulator after building the shared toolbar/observer patch. This is limited smoke evidence, not the full acceptance matrix.
- Dedicated test app and QA harness installations succeeded, but simulator launch stalled before the application executable appeared. Restarting the dedicated devices and trying a clone of a previous compact device did not resolve this. CUA could read the simulator window/screenshot, but coordinate interaction failed with `noWindowsAvailable` and the app did not start. Pending launches were cancelled and owned failed devices shut down; the other task's simulator was untouched.
- Independent QA prepared an actual UIKit observer harness (including old-implementation sensitivity and toolbar label layout checks), compiled it, and reviewed the code. The harness did not execute; its 27 planned checks MUST NOT be reported as passing. Harness and review: `/tmp/tennis-notification-observer-qa/`.
- Full 0/1/30 rows, long-text scrolling, delayed/offline refresh, compact/large-text full-navigation-bar bounds, repeated/cancelled edge swipes and physical-device hang resolution remain UNVERIFIED.
- No application was installed on the physical iPhone, no production changes and no TestFlight upload. The user has been asked to leave the actual hang open for a diagnostic capture. This is a built candidate correction, not a confirmed production resolution.
