# Photo report opening and personal visits in profile

## Request and acceptance

Open past-game report photos by tapping their thumbnails in Upcoming games. Include personal-visit photo reports in the signed-in owner's Profile game feed.

- Shared gallery opens the tapped photo, preserves original proportions, provides all ordered photos (including those beyond four thumbnails), paging/count, accessible close and loading/error states.
- Upcoming game and personal-visit thumbnails use the shared gallery. Existing report confirmation actions remain intact.
- Profile combines existing eligible game entries with completed, ended personal visits containing photos. Preserve game eligibility: ended and report visibility `profile`, or outcome `played` when no report exists. Do not change public profiles or privacy.
- Typed entries use namespaced IDs, descending activity dates with stable ties, and the existing six-item limit applied after merging.
- Load both existing endpoints; refresh on entry, foreground and pull-to-refresh. Discard old-account/stale responses. Partial fetch failure must not masquerade as an empty feed.

## Design and ownership

Product/Architect inspected existing source and froze requirements before implementation. The personal-activities endpoint is already scoped to the authenticated user and includes ordered photos and court information. No API, backend or schema change is needed.

- Profile/mobile specialist: Profile loading/feed, shared gallery file and Xcode registration.
- Discover/mobile specialist: only Upcoming report thumbnail interactions in DiscoverView.
- Root: orchestration, task packet, integration build and verification.
- Architect/QA: independent final acceptance review.

Preserve all earlier dirty changes, particularly Discover's AnyView runtime fix and native map interactions. Baseline files saved under `/tmp/tennis-report-feed-baseline`.

## Domains and risks

Affected: owner profile feed and display of existing game/personal-visit reports. Sport and court metadata are displayed unchanged. No changes to matching, geography, scheduling, lifecycle transitions, chat, notifications, reliability or premium. Personal visits remain owner-only; no fabricated multiplayer confirmation status.

Risks: large image memory, wrong initial index/duplicate URLs, stale account loads, partial endpoint failures, merging before truncation. Test these with actual-source helper checks and native compilation; perform simulator interaction checks where fixtures and automation support them. No real user account or report mutations are needed for verification.

## Verification

Implemented in `ios/TennisSearchIOS/Views/DiscoverView.swift`, `ProfileView.swift`, new `ReportPhotoGallery.swift` and its registration in `ios/TennisSearchIOS.xcodeproj/project.pbxproj`. Discover changes are limited to the two existing report previews. Profile retains existing game eligibility, adds owner-only completed visit reports and uses the same gallery. Individual photos open at their exact index, and previous/next buttons and an adjustable accessible counter accompany paging.

- Native simulator build PASS, including the final stale-account entry-guard correction: `/tmp/report-gallery-native-final-build.log`. No new errors; existing video duration/Sendable warnings are outside this change.
- Actual-source eligibility/gallery helper checks: 33/33 PASS. Harness and source hashes are under `/tmp/run-report-feed-helper-tests.py` and `/tmp/tennis-report-feed-helper-hashes.json`.
- Xcode project plist validation and scoped whitespace checks PASS.
- Installed and launched successfully on the isolated TennisSearch Grid QA simulator. This is a launch smoke, not a visual flow assertion.
- Visual interaction verification blocked: native UI automation repeatedly returned stale-element error `-10005` for Simulator window selection; screenshot observations provided no image, and a fresh tool session did not resolve it. Five-photo mock fixtures were prepared only in `/tmp/tennis-report-gallery-qa`; they were not added to the product or a real account. Local fixture media server stopped after the failed UI attempt. Actual touch opening, swipe paging, display at large font sizes and save-to-return refresh remain manual verification gaps.
- Independent QA caught and fixed a stale asynchronous child starting after an account change: both source loaders now verify cancellation, captured/current account and authentication before claiming loading state, as well as before applying responses.

No backend, API, database or web code changed for this request. npm lint/test/build are not relevant reruns for this native-only change. The prior 373-test/lint/build results apply to the preceding upload-limit release snapshot; unrelated analytics work appeared concurrently in the shared backend/web tree and is not part of this packet or those results.

This task has not uploaded a new TestFlight build or deployed backend changes. The prior TestFlight 1.1 (2026090501) remains the last uploaded build.

Subsequent release: on 2026-09-06 the user explicitly requested TestFlight upload. **1.1.1 (2026090602)** was successfully uploaded from an isolated, hash-verified copy of this completed work; Apple reported package processing. See `docs/release-2026090602.md`. The marketing version was increased because Apple had closed the already-approved 1.1 train. No backend deployment was part of that upload.

## Final independent QA

PASS with a medium residual UX risk from the unavailable visual interaction check. Final actual-source helper checks remain 33/33. An additional actual-source asynchronous loader harness passes 24/24, for **57/57 total checks**. It verifies delayed old-account responses and defers, queued stale-account calls, partial failure retaining valid history, cancelled queued/in-flight requests and logout clearing without fetching. Loader harness: `/tmp/run-report-feed-loader-tests.py`; extracted Swift and source hashes are stored beside it. Final native build and whitespace checks independently confirmed.

The installed final native build launched successfully and remained running (launch smoke). End-to-end taps, swipe paging, actual image layout and large-font appearance could not be confirmed through the unavailable Simulator UI control. A real report save followed by returning to Profile is likewise a remaining manual scenario; automatic refresh wiring and asynchronous state behavior were checked in source/harnesses.
