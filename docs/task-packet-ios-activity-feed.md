# iOS training activity feed prototype

## Request and scope

User correction: a feed of training photos or videos posted by users, implemented within the current iOS application design. The prior concept focused too much on invitations and used an outdated cream visual treatment. This task delivers a native SwiftUI prototype with local data.

## Product and architecture

- Cards center on photo/video, author, sport, posting time and optional caption. No invitations, game proposals, open slots or response CTA.
- System PhotosPicker accepts 1–5 ordered media items in total, mixing images and videos. Composer shows a carousel preview, optional caption/sport and local publish. Media is required; cancel does not publish.
- Current native shell is black, with dark rounded panels, white typography and the existing five-tab navigation. Reuse native navigation and AppTheme accents where applicable.
- A labeled Feed entry on the home toolbar opens the new screen; existing discover tabs and API contracts remain unchanged.
- A screen-specific observable store owns local posts and media, retained by MainTabView. Existing PersonalActivity/GameReport are not repurposed.
- Explicit DEBUG-only launch preview supports simulator review within the real MainTabView; ordinary auth/bootstrap behavior remains unchanged.

## Ownership and sequencing

Product Analyst completed corrected scope; Solution Architect established state ownership, media lifecycle and minimal integration. Mobile owns SportsActivityFeedView.swift, ContentView.swift, the small application preview hook and Xcode file registration. Root prepares this packet and performs build/simulator verification. Independent QA reviews the stable implementation after checks.

The pre-existing edits to DiscoverView.swift and EmptyDeckView.swift belong to another task and are not modified by this implementation.

## Acceptance checklist

- Native screen follows current dark iOS design and retains real bottom navigation.
- Training photos/videos are primary. No game invitation controls appear in activity posts.
- Photo selection, preview, cancel and local publication work. New posts appear first.
- Video selection uses file transfer, plays only on explicit action and stops on dismissal/background.
- Publish is disabled without valid media and during load. Import failures are recoverable.
- Media ownership handles canceled/replaced drafts and stale asynchronous selections.
- Demo/local-only status is visible; no server upload, notification or gameplay action occurs.
- Russian and English copy uses existing localization conventions; controls are labeled.
- Build passes for the touched native surface; simulator render and applicable interactions are verified.

## Domain coverage

iOS-only presentation of author identity and sport metadata is affected. No changes to actual profile records, sport-specific levels, geolocation/district preferences, availability/time slots, proposal lifecycle, search/lobby lifecycle, discover ranking, chat/unread, notifications/devices, cancellations/no-show/reliability or premium. Web/backend/database contracts are unchanged. Fixtures never publish existing private activities.

## Checks and limitations

Required: xcodebuild Debug iphonesimulator, native visual and interaction review. npm lint/test/build and Prisma generation are not relevant to this SwiftUI-only change.

Local prototype posts and reactions do not sync. Production persistence, media upload/transcoding, public profiles, moderation and social ranking are out of scope. Validation results and remaining limitations will be recorded at completion.

## Delivery and verification

- Added `SportsActivityFeedView.swift`: native dark feed, local post store, likes, own-post deletion, photo/video composer, file transfer, image downsampling and explicit video playback.
- Added the Feed navigation entry and retained local store in `ContentView.swift`; existing five bottom tabs are preserved.
- Registered the source in the Xcode project. Added a Debug compilation condition and `-activity-feed-preview` launch path; the preview flag is always false in Release. The app bootstrap is skipped only for this isolated Debug preview.
- `xcodebuild -project ios/TennisSearchIOS.xcodeproj -scheme TennisSearchIOS -configuration Debug -sdk iphonesimulator -destination 'platform=iOS Simulator,id=F2B5A3DC-FF54-4DA0-B945-1CA3FA03C9D4' -derivedDataPath /tmp/tennissearch-activity-feed-derived CODE_SIGNING_ALLOWED=NO build`: PASS, including the final shortened composer title.
- `git diff --check`: PASS. Independent QA static review: PASS for the local prototype.
- Native runtime: installed and launched on the dedicated iPhone 17 Pro simulator; visually reviewed feed, current five-tab shell and composer. Like changed 24 to 25 with the correct accessible action. Publish is visibly disabled without media. System PhotosPicker opens and displays the gallery.
- Runtime limitation: gallery items were not exposed through the automation accessibility tree, and coordinate actions failed with `noWindowsAvailable`. Simulator test-media import also stalled. Consequently, selecting/importing photo/video, publication/cancel completion, video playback/background pause and deletion have static review but are NOT claimed as end-to-end runtime passes. These remain manual device checks before shipping.
- A copied file can remain in system temporary storage if the provider cancels between copying and returning its URL, or on abrupt termination. Ordinary cancel/replacement/delete/store teardown paths clean up owned videos. This is an accepted prototype disk-cleanup limitation.
- This task did not edit DiscoverView.swift or EmptyDeckView.swift. Their hashes matched the baseline after feed implementation; later changes from concurrent work were observed during final verification and were left untouched.

Review entry: open **Главная → Лента** in the app, or launch a Debug simulator build with `-activity-feed-preview` for direct review without an account. Demo posts are labeled and no publications leave the device. A screenshot of the running native screen is saved in the task's visualization output directory as `native-activity-feed.png`.

## Increment: multi-media posts and author profiles

User requests up to five photos in one post, swiping through media including playable videos, and navigating to the author. Product contract treats the cap as five media items total, in any photo/video combination. This increment remains a local native prototype.

Approved architecture: Mobile changes only SportsActivityFeedView.swift. Stable local author IDs map to local profile metadata; local fixtures never resolve to a real user by display name. Posts store ordered identifiable media items. A reusable paged carousel reports its current index and controls per-page video playback. The composer adds/removes media up to remaining capacity and transfers ownership of published video files to the retained store. Author profile sheets read the same store and display only that author's posts.

Acceptance for the increment:
- Enforce 1–5 mixed media items at selection and publication boundaries; preserve selection order.
- Add/remove items without losing caption/sport, disable add at five, disable publication when empty/loading/already submitted.
- Recover per-file import errors without empty slides, stale asynchronous insertion or leaked ordinary canceled drafts.
- Support horizontal paging and a visible current/total indicator; removal maintains a valid selected page.
- Video playback is explicit and pauses on page change, leaving the viewport, opening author/composer, leaving the feed or app backgrounding.
- Author name and avatar open the correct local profile, with bio/sport and that author's publications; return preserves feed state.
- Shared likes/deletion remain consistent between author profile and feed; no gameplay/API effects.

Product scope was reviewed by Product Analyst. Solution Architect defined the contract before Mobile implementation. Independent QA uses this checklist after the stable build. Root updates documentation, builds and verifies the native screen. Earlier verification results above refer to the single-media prototype; updated results will be appended for this increment.

### Increment delivery and verification

- Changed only `SportsActivityFeedView.swift` for this increment, plus this task packet. Added ordered mixed-media arrays, a paged carousel with counter and accessible previous/next controls, remaining-capacity selection and per-item removal. Author name/avatar opens the author’s local profile and posts from the shared store.
- Native Debug simulator build: PASS; log `native-feed-carousel-build.log` in the task visualization directory. Scoped whitespace check and independent QA final static review: PASS, no blockers. Web/npm and Prisma checks do not apply because these surfaces and contracts were not changed.
- Runtime on the dedicated iPhone 17 Pro simulator: PASS for distinct first/second photos and counter 1/2 → 2/2, author profile with correct bio/sports and one matching post, dismissal preserving feed page, and a like changing 24 → 25 and remaining 25 in the author profile. Composer displays 0/5; PhotosPicker opens with the system “maximum 5 objects” notice and both seeded video and photo assets.
- Runtime gap: the system gallery does not expose its items to this automation session and coordinate selection fails with `noWindowsAvailable`. Thus importing/publishing five mixed items, individual removal, actual video playback and its pause transitions are statically reviewed but are not claimed as end-to-end runtime passes. Check these on a device before release.
- Per-file ownership now cleans partial copies and canceled transfer results, resolving the earlier ordinary cancellation gap. Abrupt process termination can still leave system temporary files. Five maximum-size videos can temporarily occupy about 1 GB; photos are downsampled to 1,600 pixels.
- Posts, likes and profiles remain a labeled local prototype in memory, with no upload, backend persistence or real-account profile integration. No database/API changes. Concurrent Discover/EmptyDeck work was left untouched.
- Native review images: `native-feed-carousel.png` and `native-feed-author.png` in the task visualization directory.

## Increment: optimized autoplay, player interest and place tags

User requests automatic optimized video playback, a match action from another player’s profile, and tagging the club/location where they played. This extends the current native local prototype; the previous explicit-play requirement is superseded by autoplay.

Product Analyst defined acceptance; Solution Architect inspected existing Court, AddressSuggestion, repository and matching contracts before Mobile implementation. Mobile owns only `SportsActivityFeedView.swift`; root owns this packet, build and simulator checks; independent QA reviews the frozen result. Concurrent changes to other native files are preserved.

### Approved contract and acceptance

- One shared AVPlayer for the activity surface, muted by default. Only the current video slide with at least 60% visibility competes for playback; prefer the closest to the viewport center with stable ties. No eager player per carousel item.
- Release the current AVPlayerItem when nothing is eligible. Pause on slide/viewport/tab/sheet/scene transitions; user pause is respected and accessible sound/play controls are available. Inactive cells display a poster/placeholder. Remain compatible with iOS 16.4.
- Other authors have a “Хочу сыграть” action with an idempotent local interest state and cancellation. Own profile has no self-action. Demo IDs never call real matching APIs or imply a reciprocal match. Real accounts would later reuse the existing repository matching contract; this increment adds no matching rules.
- Optional club selection reuses Court catalog data; the post stores a snapshot of club identity/name and its selected public address/coordinates. Standalone places use existing AddressSuggestion search data, with an honest text-only fallback if needed. Editing a standalone place clears an incompatible club; removal cannot leave hidden stale coordinates. No automatic GPS or media EXIF publication.
- Places are visible in composer before publication and in both feed/profile posts. Missing place, unavailable search and empty catalog do not block publication. Existing 1–5 ordered mixed-media, removal/import cancellation and shared-like behavior remain acceptance checks.
- DEBUG-only fixture injection, requiring the existing preview flag and a local container clip, can seed labeled QA media and diagnostic state for real-player runtime checks. Release ignores these arguments. This does not count as PhotosPicker import coverage.

### Domain coverage and verification plan

iOS presentation, local author interaction and optional activity location metadata change. Existing user profiles, sport levels, preferred districts, availability, game requests/lobbies, ranking, chat/unread, notifications/push, cancellations/reliability and premium remain unchanged. No backend, schema or shared API changes, and no messages are sent to other users.

Required checks: native Debug simulator build, independent QA review, scoped whitespace check and native interaction checks. Use injected video to verify time advances automatically while muted, manual pause holds and playback stops or switches on transitions. Verify local interest and venue selection in the actual UI. npm/Prisma checks remain irrelevant to this native-only increment. Record unavailable checks and remaining prototype limitations below.

Implementation reference: Apple documents that attaching an AVPlayerItem is the signal to load its media, and that AVPlayer can be reused by replacing its current item. The shared-player approach therefore avoids attaching every video in a five-item post. See [transport behavior](https://developer.apple.com/documentation/avfoundation/controlling-the-transport-behavior-of-a-player) and [AVPlayer](https://developer.apple.com/documentation/avfoundation/avplayer). No device performance benchmark is implied by this architectural check.

### Delivery and validation

- Implemented in `SportsActivityFeedView.swift`: one reused AVPlayer, strict candidate ordering with hysteresis, 60% eligibility, default mute, play/pause and sound controls, item release with no eligible candidate, explicit modal blocking and a lightweight inactive-video placeholder. Carousel owns registration independently of preloaded TabView pages.
- Added local “Хочу сыграть” / “Отменить интерес” state to other authors’ profiles. This is an expression of interest in the prototype; no reciprocal or server match is claimed.
- Added optional exact-place picker using the existing Court and AddressSuggestion contracts, searchable city/address, cancellation/debounce, error/retry states and a text-only fallback. A whole-tag snapshot prevents stale club/coordinate pairs. Selected tags appear on feed/profile cards and open a native place detail with a map when coordinates exist.
- Native Debug simulator build: PASS after final carousel registration fix (`native-feed-autoplay-build.log`). Independent QA final review: PASS. Whitespace checks: PASS. No npm/Prisma changes or applicable checks.
- Runtime initially found a real defect: page-level TabView appearance did not register the first visible video. Moving registration to the carousel fixed it; the new build auto-started the injected local clip without a tap.
- Actual AVPlayer diagnostics: time advanced from 5.682126666 seconds with `timeControlStatus=2` (playing) to 18 seconds at clip end, with `isMuted=true`, one loaded item and the same player identity. The fully visible first video had fraction 1; the offscreen second video had fraction 0 and was not loaded. Screenshot `native-autoplay-qa.png` shows the rendered test clip; `autoplay-running.json` stores the later end-of-clip snapshot. The fixture is clearly marked QA and is not a real training post.
- Native UI access recovered in the QA agent’s fresh session. Replay and Pause changed the actual controls; page 2/2 displayed a photo, returning to 1/2 retained manual pause. The saved `autoplay-manual-pause.json` confirms status 0 and `manuallyPaused=true`; a later snapshot after opening the own profile retained time 0 and the same player/media with a new render ID while feed candidates were inactive. Own profile showed two matching QA posts and no self-match action.
- Other-author runtime: Anna’s “Хочу сыграть” changed to “Отменить интерес” with local-only wording, then cancellation restored the initial action. Composer fixture auto-played; sound control switched to the unmuted symbol. Choosing Tennis Prime filled the composer with “Аптекарская наб., 7” and the remove-place control. Reopening the place picker produced `modalBlocks=1`, zero candidates, zero loaded items, no active media and paused status, corroborated in `autoplay-place-modal.json`.
- Place replacement/removal runtime: choosing Padel Club North changed both club and address to “Пр. Медиков, 5”; removing the place restored “Добавить клуб или место” and removed the clear control. Review images: `native-feed-profile-interest.png`, `native-feed-place-picker.png`, `native-feed-composer-place.png`. The simulator is restored to the ordinary local preview without QA fixture posts after verification.
- Publishing the selected place could not be completed by UI automation: the composer’s visible navigation toolbar is absent from its accessibility tree and coordinate actions fail with `noWindowsAvailable`. Publishing/place display and map detail therefore retain static coverage; do not claim a full end-to-end publication pass. This is independent of the successful playback, interest and place-selection runtime checks.
- Remaining checks: PhotosPicker import is still separate from fixture coverage. Real-device performance, mixed codecs and online venue search have not been benchmarked/tested. User data and interests remain local/in-memory; no backend/schema, ranking, chat or notification changes. Inactive videos deliberately have a lightweight placeholder, with no speculative preloading. Abrupt termination can leave OS temporary files; source-video metadata is retained locally and requires a separate policy before future upload support.
