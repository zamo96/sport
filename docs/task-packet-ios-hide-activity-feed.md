# Temporarily hide the iOS activity feed

User explicitly requested removal of feed access while the physical-device hang remains unresolved. This supersedes further speculative hang fixes for now.

## Scope and design

Mobile owns removal of the Home toolbar entry, feed navigation destination, debug preview route, and eager feed store/presentation state from ContentView. Disable the preview launch helper in every configuration so old debug arguments cannot bypass onboarding or bootstrap. Keep the feed implementation and local media intact for later restoration. Preserve all concurrent changes and earlier Discover corrections.

Only iOS navigation/feature availability is affected. Profile data, sports/levels, geolocation, availability, game/search lifecycle, ranking, chat, notifications, reliability and premium rules are unchanged. No web, API, database or contract changes.

## Acceptance and ownership

Root coordinates snapshot, native builds, installation and reporting. Mobile implements the narrow route removal; independent QA checks standard Home and legacy preview-flag launch, with no feed entry and other tabs preserved. No new implementation-mirroring tests for this reversible removal. Native simulator build, static reachability review and runtime smoke checks are required; signed device build/install when available. npm/Prisma checks do not apply to this native-only scope.

Users with older installed builds retain their previous UI until they update. This task does not publish to TestFlight or App Store.

## Validation

Implemented in two native files: ContentView removes the feed entry, navigation/preview route, presentation state and eager store; SportsActivityFeedPreview returns false in every build. The bootstrap guard therefore follows the normal path even when the old preview argument is provided. No feed view/store construction calls or preview launch-flag readers remain in the native app. Source whitespace validation passes.

Frozen 96-file native snapshot: `/tmp/tennissearch-hide-feed-20260906`, SHA-256 manifest included. Native simulator and signed device builds are running. Independent QA reviews the before/after diff against `/tmp/tennissearch-hide-feed-baseline`.


Both frozen native Debug builds PASS with zero compiler errors: `/tmp/tennissearch-hide-feed-simulator-build.log` and `/tmp/tennissearch-hide-feed-device-build.log`. Independent static reachability review PASS. Signed development app installed on iPhone Matvey (container FBA10ED5-7E3D-4A41-8503-105E4C374A35) and launch confirmed, preserving observed local backend settings and app data. Logs `/tmp/tennissearch-hide-feed-device-{install,launch}.log`. Both task-owned Swift files still match the snapshot manifest; `git diff --check` PASS. Simulator runtime review PASS: normal Home has no feed entry; Cards → Grid → Cards responds; Matches retains the guest email gate and Home returns. Relaunch with the legacy `-activity-feed-preview` argument shows the same normal five-tab Home, without the feed. Screenshot `/tmp/tennissearch-hide-feed-preview-ignored.png`. No app data reset. Onboarding/bootstrap bypass prevention is verified statically; a fresh onboarding runtime was not separately exercised because the fixture already has guest access.

Completion: temporary removal accepted. This does not establish repair of the underlying iOS 18 hang. Existing distributed builds need an update to receive the removal; no TestFlight/App Store release was performed.
