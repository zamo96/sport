# Activity feed responsiveness

## Scope and ownership

User reports that the native activity feed is very slow. Preserve all existing design and behavior: mixed 1–5 media, autoplay/manual pause, profiles and local interest, optional club/place tags, publishing and deletion. No domain/API/database changes. Other current checkout edits, including upload work and discovery/map changes, are outside this task.

Product Analyst defined the performance/regression criteria. Solution Architect identified repeated synchronous photo loading during SwiftUI body evaluation and redundant playback updates. Mobile owns only SportsActivityFeedView.swift. Root owns baseline capture, profiling, this packet and native builds/device installation; independent QA reviews and checks the stable result.

## Design

- Load and decode photos on a serial background worker; coalesce shared loads and bound a decoded-image cache. Preserve the existing maximum 1,600-pixel preparation quality. The view body only displays ready images or a placeholder.
- Prepare imported images off the main actor while keeping temporary-file ownership, cancellation and generation guards.
- Make playback updates idempotent: unchanged/no candidate does not publish state or send repeated AVPlayer commands. Photo-only carousels do not drive selection. Mixed video→photo transitions still unregister immediately.
- Keep one visible selected autoplay player, default mute, explicit manual pause, scene/modal/offscreen stopping and stable carousel ownership.
- Performance counters/diagnostic output are explicit DEBUG-only tools; no per-geometry/KVO synchronous disk output, and no more than two timer snapshots per second.

## Acceptance and evidence

- Photo scrolling, photo/video paging and control feedback remain responsive without silently disabling requested features.
- Cached revisits do not repeatedly decode the same image; inactive/unchanged media does not repeatedly publish playback state or issue play/clear commands.
- Cache/load tasks are bounded, do not resurrect cancelled imports and do not accumulate players across profile round trips.
- Native Debug simulator and signed-device builds pass. Verify autoplay, manual pause, paging, profiles and optional place controls with available runtime tooling.
- Compare physical before/after timings only if dataset and interaction sequence are comparable. Source reductions and counters are implementation evidence, not proof of a particular FPS or percentage improvement.

Baseline source is `/tmp/tennissearch-feed-performance-before.swift`. A 20-second Time Profiler recording attached to the running app on the connected iPhone is `/tmp/tennissearch-feed-before.trace`; without a controlled interaction sequence this is diagnostic evidence, not a benchmark. User was asked where the slowdown is most noticeable while work continues.

Web/npm/Prisma checks do not apply to this native-only fix; concurrent web/upload changes are not owned by this task. Results and limitations are recorded below.

## Implementation notes

Mobile changed only `ios/TennisSearchIOS/Views/SportsActivityFeedView.swift`. The shared serial ImageIO loader uses a 12-item / 32 MiB NSCache budget and prepares up to 1,600-pixel images. View-held images are additional to the cache budget; this is not a cap on the entire feed's memory. Temporary imported files remain owned through background decoding, with the existing cancellation and import-generation checks before publication.

Single attachments bypass the page TabView; mixed/multiple attachments keep paging, and playback registration remains on the stable outer carousel. Playback reconciliation covers a brief visibility-threshold exit/re-entry while respecting manual pause. DEBUG counters are enabled only by the existing local video-fixture flag. JSON serialization and writes run on a utility queue, with at most one write in flight and a 0.5-second timer.

The physical baseline trace exported 222 main-thread samples, mostly SwiftUI AttributeGraph work, without attributable feed/image symbols. No specific frame-rate improvement can be inferred from this uncontrolled recording. The current iPhone has a newer installed build from a separate release task; this task does not overwrite it or publish a TestFlight update.

## Verification

- PASS: required Debug simulator build (arm64 and x86_64), log `/tmp/tennissearch-feed-perf-simulator-build.log`.
- PASS: signed Debug generic iOS device build, log `/tmp/tennissearch-feed-perf-device-build.log`. Explicit production HTTPS configuration and mock-data disabled were verified in the resulting Info.plist. Existing ProfileView duration/sendability warnings remain outside this change; there are no feed compilation errors.
- PASS: independent QA source review of background decoding, temporary-file ownership, cancellation/generation checks, stable carousel registration, playback reconciliation, and timer-only background diagnostics.
- Runtime build installed only on the dedicated `TennisSearch Activity Feed` simulator, UUID `F2B5A3DC-FF54-4DA0-B945-1CA3FA03C9D4`. Fixture launched successfully; initial snapshot shows one player, one loaded item, muted playback, one play command and one item replacement. Behavioral checks follow below.
- PASS: four seconds of active playback (12.155 → 16.155 seconds) kept the same player and left every performance counter unchanged: no extra candidate selection, state publication, player command, item replacement, or image decode. `/tmp/tennissearch-feed-perf-idle.json` contains both snapshots.
- PASS: paging from video to photo unloaded the current player item and removed the candidate. A repeated photo load hit the cache without another decode; `mainThreadPhotoDecodes` remained zero. Snapshot: `/tmp/tennissearch-feed-perf-photo.json`.
- PASS: further cache revisit reached two cache hits with one total decode and zero main-thread decodes. Manual pause survived profile navigation and carousel revisits, with one player instance. Snapshots: `/tmp/tennissearch-feed-perf-cache-revisit.json`, `/tmp/tennissearch-feed-perf-profile-paused.json`.
- PASS: place-picker modal set one block, unloaded the player item and stopped playback; choosing TennisPrime restored its paired title/address and single-item composer playback. The same player instance was retained. Snapshot: `/tmp/tennissearch-feed-perf-modal.json`. QA published nothing.
- Independent QA final scoped verdict: PASS. Full scrolling performance, import stress/PhotosPicker end-to-end and physical-device before/after FPS remain unverified because native accessibility scrolling failed (`noWindowsAvailable`) and the physical recording was not a controlled comparison. This verifies the targeted work reductions and playback regressions, not a guarantee that every reported hitch is resolved on the user's installed version.
