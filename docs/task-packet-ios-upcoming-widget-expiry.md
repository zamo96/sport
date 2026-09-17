# Upcoming widget keeps completed personal visit — 2026-09-13

## Scope and acceptance

The user reports an old personal visit remaining in the iOS upcoming-games widget even after a subsequent scheduled game has also passed. The widget must select an ongoing or future dated event, remove an event at its scheduled end, advance to the next cached event, and show empty state when all cached events have ended. This must work with cached data when a network refresh fails. Completed visits and games remain available in app history.

Affected surface: iOS home-screen widget and its app-side cache writer. Affected domains are display of personal activities and game-request schedules. Profile, sport levels, geolocation/preferences, availability editing, game-search lifecycle, discover ranking, chat/unread state, notification campaigns/push devices, cancellations/no-show/reliability rules, premium, and backend/API/schema are unchanged. Live Activity behavior is outside this correction.

## Root causes and design

1. The app's cache writer reuses in-app archive predicates. These retain completed personal visits and games needing outcome review, allowing old records to occupy the first three widget cache slots.
2. The widget creates future timeline entries with identical payloads and always renders the first record. Passing the end boundary never removes that record from the cached timeline.
3. Remote refresh is scheduled from the final future timeline entry, potentially delaying new-event discovery for days.

Both affected files matched the frozen uploaded 1.2.1 (2026090901) release before editing. Independent actual-source baseline harnesses reproduced: an expired visit remained first in all 34 generated entries; an event three days away delayed refresh by 4,515 minutes; an end time with fractional seconds had no exact expiry entry; three old planned visits displaced the next game from all three app-cache slots.

Use widget-specific time eligibility before limiting cached records; project each timeline entry against its own date; preserve exact end-time transitions, including seconds, despite countdown-entry limits; request network refresh from the current date. Recompute relative date labels for each entry. Keep app history and Live Activity grace periods unchanged. Exclude undated events from this scheduled-event widget; handle absent/invalid durations consistently with the event defaults.

## Ownership and checks

- Product/architecture: `widget_staleness_design`, read-only diagnosis and requirements.
- Mobile: `widget_staleness_mobile`, widget extension/cache writer and focused actual-source Swift regression tests.
- Independent QA: `widget_staleness_qa`, acceptance review and edge cases.
- Orchestrator: source/build verification and this task packet.

Required validation: actual-source Swift tests and full iOS simulator build including the extension. Web/npm/Prisma checks do not apply unless those surfaces change. Preserve unrelated existing working-tree changes. No release upload or backend deployment is included in this implementation task.

## Delivery and limits

Implementation is limited to `ios/TennisSearchUpcomingWidget/UpcomingGamesWidget.swift` and `ios/TennisSearchIOS/Services/UpcomingGamesWidgetStore.swift`, with regression tests in `ios/Tests/UpcomingGamesWidgetTests.swift` and `ios/Tests/run-upcoming-games-widget-tests.sh`. No project-file or version changes. App history and Live Activity implementation are preserved. The widget now requests refresh within 15 minutes from now (or an earlier start/end transition), while iOS controls actual execution. Each remote request has a 10-second timeout so errors can reach the cache fallback.

Actual-source regression tests: **PASS, 34 extension checks + 6 app-store checks**. The runner compiles production provider/projection/cache-writer logic with framework and unrelated presentation model stubs; actual personal-activity history behavior is included. Independent QA repeated all 40 checks under Pacific/Auckland and America/Los_Angeles, both PASS. Tests cover exact fractional-second expiry, advancement and empty state, filtering before the three-event cap, terminal/undated/invalid-duration records, remote mapping, disabled-remote cache fallback, distant events and countdown budget, midnight and overnight changes, and refresh timing. Independent source review PASS; Live Activity implementations remain unchanged.

Full required Xcode Debug simulator build: **PASS**, app and embedded widget extension built for arm64 and x86_64 (`/tmp/tennis-widget-expiry-build.log`, derived data `/tmp/tennis-widget-expiry-derived`). Product/configuration source integrity verified against `.artifacts/widget-expiry/build-source-manifest.json`; only the test file changed after capture. Existing unrelated ProfileView deprecation/concurrency warnings remain. `git diff --check` for the touched production files is clean.

The existing cache capacity of three events remains a bounded offline limitation: newly created or uncached events require a successful refresh. Physical-device behavior and iOS scheduling remain separate from deterministic timeline verification. Delivery to installed applications requires a new iOS build; no TestFlight upload is performed by this task.
