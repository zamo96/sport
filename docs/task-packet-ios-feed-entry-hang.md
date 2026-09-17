# Feed entry hang

User reports that opening the feed freezes the application after the earlier media optimization. Treat this as an unresolved entry/navigation defect, not proof that media decoding is still the cause.

## Scope and owners

Product Analyst: normal Home → feed acceptance. Architect/Mobile: inspect and implement the smallest native correction after evidence. Root: baseline reproduction, hang capture, builds and integration. Independent QA: actual-route regression review. Preserve all concurrent checkout edits. No API, database, ranking or other product-domain changes.

## Acceptance

Open normally through the Home toolbar, with default photo-only posts. Confirm first rendering, interaction and back navigation. Repeat five times and after author/composer dismissal. Preserve multi-media paging, autoplay, manual pause, profiles/local interest and place tags. Preview-only tests do not establish entry-path correctness.

## Baseline

Frozen entry sources: `/tmp/tennissearch-feed-entry-before.swift` and `/tmp/tennissearch-feed-entry-content-before.swift`. Dedicated simulator: `F2B5A3DC-FF54-4DA0-B945-1CA3FA03C9D4`. Initial native build uses mock data for deterministic normal entry, not the direct feed preview flag. Device app was not running at the first process inspection; no freeze stack captured yet.

## Diagnostic results

- Architect found no source-level deadlock: the store exists before entry, initial posts contain photos only, background photo loader does not synchronously wait, and photo geometry does not publish playback updates. Normal navigation also runs Discover disappearance/layout hooks; this is a hypothesis to inspect in a stack, not an established cause.
- First simulator build failed because the Mac volume ran out of space (128 MiB available). Removed only this task's previous disposable `/tmp/tennissearch-feed-perf-device-derived` build cache. Retried build PASS: `/tmp/tennissearch-feed-entry-baseline-build-retry.log`. No product code changed.
- Original simulator boot failed with launchd timeout. A separate fresh QA device `71287633-1641-495D-95B7-EE361FAE52BB` (`TennisSearch Feed Entry QA`) also has not completed boot. Other tasks' running simulators and the shared simulator service were not reset.
- Connected iPhone has installed 1.1.1 (2026090602). Launch was denied by iOS because the device is locked; log `/tmp/tennissearch-feed-hang-launch.log`. Asked the user to unlock it and reproduce entry for hang sampling. No new build installed on the phone and no TestFlight upload.
- Concurrent Centers work changed ContentView while this investigation was running; preserve that work. Entry snapshots above are diagnostic baselines, not permission to restore the shared file.

Status: unresolved, waiting for usable runtime reproduction/stack. A passing build and static review do not establish that the reported hang is fixed.

## Live capture and targeted correction

After the user opened the hung feed, captured a 15-second Time Profiler recording from iPhone PID 3803: `/tmp/tennissearch-feed-entry-live.trace`, exported `/tmp/tennissearch-feed-entry-live-samples.xml`. The capture contains 15,357 main-thread samples: almost all include UIHostingView layout and AttributeGraph updates, with DiscoverView/SwipeCard and LazyStack estimation frames. No named feed decoder/player stack was implicated. Independent QA confirmed the stack analysis. These are overlapping sample counts, not exclusive CPU percentages.

The actual running binary UUID `A1BAF90D-966E-3A3A-B128-5E3F20B5252F` matches the local Xcode Debug binary, rather than the archived TestFlight dSYM. Its observed configuration is HTTP `192.168.0.102:3000`, mock data NO, debug trust YES. The replacement diagnostic build preserves those settings; it is not a production release.

Architect/Mobile changed only DiscoverView.swift:

- Move scroll-offset measurement out of a virtualized lazy child into the stable stack background; preserve spacing/padding and the pinned header.
- Ignore hidden/nonfinite scroll updates, clamp to the 110-point range consumed by the collapse effect, and skip sub-half-point changes.
- Normalize geometry to pixels, skip repeated coordinates, and ignore hidden-screen changes while retaining initial measurement.
- Stop the story timer from mutating an already-paused state on every tick; existing visibility/playback transitions own pausing.

Pre-edit Discover source: `/tmp/tennissearch-feed-entry-discover-before.swift`. Both builds use a frozen 94-file native snapshot at `/tmp/tennissearch-feed-entry-fix-20260906`, with a SHA-256 source manifest, to avoid concurrent workspace edits affecting verification. The fresh dedicated simulator now boots after disk space was recovered.

### First correction validation — insufficient on iPhone

- Debug simulator and signed device builds PASS; logs `/tmp/tennissearch-feed-entry-fixed-{simulator,device}-build.log`. Frozen actual-source clock tests PASS (39 assertions).
- Independent normal-route simulator QA PASS: five Home → Feed → Home cycles, photo paging, author profile, composer open/cancel, Cards/Grid switching. This is iOS 26.3.1 evidence only.
- Installed on iPhone after connection recovery; successful log `/tmp/tennissearch-feed-entry-device-install-connected.log`. Launch PID 5587 in the new app container confirmed.
- User explicitly reports that the iPhone still hangs. Therefore the first correction is insufficient and the issue remains open.
- Repeat profiler attempts could not find the process; later Xcode device screenshot showed SpringBoard, so those failed recordings do not provide a post-fix hang stack or evidence of improvement.
- Next design: explicitly mark Discover covered before pushing the feed, preserving its mounted identity/state; pause decorative TimelineView and sport-chip animation in addition to media/progress timers. Waiting until onDisappear can leave the source active during a stalled navigation transition.

### Second correction validation — insufficient on iPhone

V2 adds binding-driven navigation in ContentView and a default-true `isForeground` input to Discover. This pauses source geometry/media/progress, ambient TimelineView and chip animation before the push. Frozen actual-source tests PASS (39), Debug simulator/device builds PASS, and five normal push/pop cycles on the simulator preserve Grid/Card selection and source state. Physical install and launch of PID 5647 confirmed, but the user again reports a hang. Overall V2 result: FAIL on the target iPhone.

Retrieved iOS CPU report through Xcode Devices → Open Recent Logs: `/tmp/tennissearch-feed-entry-v2-cpu.ips`. It matches the installed V2 UUID `893B6B8C-D61D-324E-87CF-3D5C0F470CA5`. Over about 100 seconds it records 90 seconds of CPU time; footprint grew 39.45 → 817.80 MiB. System and application symbols resolve back to DiscoverView.body, tabContentContainer, swipeContent, SwipeCard and SwiftUI layout. Full resolved report: `/tmp/tennissearch-feed-entry-v2-cpu-all-symbolicated.txt`. The report says action taken `none`; it does not prove a watchdog kill.

The user clarified that the feed previously opened without this hang. HEAD's Discover body uses an ordinary VStack, while the recent working tree added an outer LazyVStack with pinned Section. That outer container virtualizes only a handful of large children; actual long collections have their own lazy containers. V3 therefore restores a stable outer VStack on iOS 17+, retaining pinned controls with a pure visual offset and keeping inner lazy collections. Existing iOS 16.4 pinned Section remains as the compatibility path. This is a controlled layout correction; the exact SwiftUI internal defect is not established by the sampled stacks.

### Third correction — device validation pending

V3 restores the stable outer VStack on iOS 17+, with `visualEffect` pinning the existing controls. Inner lazy lists, Cards/Grid identity and existing scroll anchors remain. iOS 16.4 retains the prior pinned Section compatibility path. Both frozen-snapshot Debug builds PASS (`/tmp/tennissearch-feed-entry-v3-simulator-build.log`, `/tmp/tennissearch-feed-entry-v3-device-build.log`); independent static review and `git diff --check` PASS.

Installed V3 on the dedicated simulator and physical iPhone without deleting app data. Device launch succeeded as PID 5721 in new container DE3E87F5-803E-4346-B0B3-BEC9CA9D366C. Asked the user to verify scrolling/back and leave the feed open. An initial post-launch Time Profiler attach could not find PID 5721; this is a capture limitation, not evidence of success or process termination. QA is checking normal simulator navigation and pinned controls.

At final source comparison, DiscoverView and SportsActivityFeedView still match the V3 build snapshot. Concurrent work changed only ContentView's top-level authentication/onboarding gate after the snapshot (MainTabView navigation correction remains identical); those unrelated changes are preserved and are not covered by this frozen build. No web/backend/schema changes belong to this correction, so npm/Prisma checks are not applicable to its isolated scope.

V3 simulator QA PASS: five normal toolbar pushes and actual navigation pops; Grid state preserved, Cards restored, Anna photo page 1→2 and author-profile dismissal preserve the selected page. Viewed-tray scrolling keeps the panel at the top and its AX actions respond. Coordinate hit-testing remains unverified because CUA returned `noWindowsAvailable`; screenshot `/tmp/tennissearch-feed-entry-v3-sticky.png`.

Fresh physical report `/tmp/tennissearch-feed-entry-v3-crash.ips` matches V3 UUID `3F6FB4E8-8A2A-3A6D-A7DD-05F79DDF1125`, PID 5721. It launched 18:59:22 and was killed at 18:59:47 by the process-exit watchdog after failing graceful termination in 5 seconds. Main thread is busy in 200 frames of SwiftUI size/alignment calculation; only app frame is main. This establishes an unresolved physical responsiveness/termination problem but cannot identify which screen was visible or prove a feed-entry event. Overall acceptance remains unresolved.

A new launch-based Time Profiler recording succeeded (`/tmp/tennissearch-feed-entry-v3-launch-profile.trace`, PID 5746, 19:02:13–19:02:29). Export `/tmp/tennissearch-feed-entry-v3-launch-samples.xml`; analysis pending. Unlike the failed attaches, this is a valid recording of the installed V3 binary.

Launch-trace analysis: the recorded screen was AuthView/welcome onboarding (OnboardingLoopingCards, OnboardingPreviewCard, OnboardingTypewriterLine, KeyboardWarmup), with zero Discover/SwipeCard/feed frames. Main-thread sample weight is 2.513 s over a 15.063 s sampled interval; layoutSubviews appears in 163 samples. This is not reproduction of the original continuous Discover layout hang and cannot establish V3 success or failure for feed entry. Analysis `/tmp/tennissearch-feed-entry-v3-launch-analysis.json`. Asked the user which screen is currently visible before attempting more code changes or phone interaction. Current final status: V3 builds/static/simulator PASS; physical normal-route acceptance PENDING. The observed process-exit watchdog is retained as a risk, with its screen unspecified. No speculative V4 was implemented.


## User-directed containment

The user subsequently requested temporary removal of feed access from iOS. Further hang experimentation is superseded by that explicit scope. Entry/navigation/preview access has been removed and validated under `docs/task-packet-ios-hide-activity-feed.md`; the underlying hang remains unresolved and must be revisited before re-enabling the feature.
