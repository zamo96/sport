# iOS: next step after the last player card

## Scope and intent

Improve the native empty-deck screen for an early, small user base. Make the
existing create-search flow the main next step; preserve club browsing and the
personal invitation link. This task changes iOS presentation and navigation only.

## Acceptance criteria

- The empty deck has a clear primary action opening the existing search composer.
- A known owned, active, unexpired hot search provides a route to existing searches.
- Empty-state text does not infer city population from the current card count.
- Club and sport-catalog navigation and the native invitation share sheet work.
- Loading, failed loading and an empty club list leave the primary action available.
- Ancillary content is not reused across accounts; retry and concurrent loading are safe.
- Motion is optional; manual scrolling, accessible labels, large text and RU/EN work.
- The complete iOS target builds and the actual view is visually checked in Simulator.

## Design and ownership

Product Analyst and Solution Architect supplied read-only scope and design reviews.
Frontend/Mobile owns `EmptyDeckView.swift` and integration in `DiscoverView.swift`.
Orchestrator owns this packet, build and visual verification. QA independently reviews
the final diff against these criteria after the implementation and required checks.

Use the existing `presentHotSearchComposer`, `SearchComposerView`, `.searches` route,
`pendingCourtID` and sport catalog routes. The server remains the source of data.
No API, database or recommendation-score changes are part of this task.

## Domain coverage

Profile, sport/level, location, availability: existing context only.
Game-search lifecycle: entry into existing creation/management flows only.
Game proposals, matching/ranking, chat/unread, notifications/push,
cancellations/reliability and premium: no rule changes.
Web and backend: unchanged. iOS: presentation and navigation changed.

## Known limits

- The discover view's own-search list currently includes hot searches only.
- Empty-deck club payloads have no court city or photo field; the redesign must not
  invent them or describe global activity counts as personal matches.
- Server-side club city filtering and recommendation analytics are separate work.
- Fixture-based visual checks do not verify live server responses or delivery of invitations.

## Delivered

- Compact emerald hero with Create search / My searches and a conditional training recommendation.
- Larger club cards with manual scrolling, catalog action and existing destinations.
- Invitation card with native sharing, copy-link feedback and accessibility announcement.
- Honest empty copy, ancillary loading/error/retry, and account-scoped cache handling.
- Empty decks no longer show the swipe instruction bar.

## Verification — PASS

- Required `xcodebuild -project ios/TennisSearchIOS.xcodeproj -scheme TennisSearchIOS
  -configuration Debug -sdk iphonesimulator build`: **BUILD SUCCEEDED**, including
  the final copy changes. Log: `.artifacts/ios-empty-deck/xcodebuild-final.log`.
- `git diff --check`: passed.
- Compiled the production `EmptyDeckView.swift` in an isolated Simulator preview host
  with fixture data. Verified actual taps for create/manage callbacks, court ID and
  sport catalog callbacks, retry, exact copied invitation URL, and native share sheet.
- Inspected RU normal-size and EN accessibility-size screenshots. The primary action
  remains readable without clipping. Empty supplementary data and active-search states
  were checked. Screenshots are under `.artifacts/ios-empty-deck/`.
- Independent QA reviewed the final source and visual evidence: **PASS**, no blocking
  findings. Dynamic Type layout, Reduce Motion branches, labels, account/request guards
  and production navigation integration were inspected in code.
- Web lint/tests/build and Prisma generation were not run: no web/server/schema files
  changed. There is no iOS automated test target in this project; the target build and
  the above simulator checks cover this presentation change.

## Residual risks and follow-up

- The preview verifies the actual screen with callbacks, not a live account's complete
  search creation or invitation delivery. No production searches/messages were submitted.
- Physical-device VoiceOver, account-switch races and the complete composer flow need
  a release smoke check; their integration was reviewed in source.
- Existing `ProfileView.swift` compiler warnings about AVFoundation deprecation and
  Sendable capture remain outside this task. The changed files build successfully.
- Active-search time is reevaluated when the view updates; no expiry timer was added.
- Club eligibility/count corrections remain a separate backend task, as scoped above.

## Follow-up: compact rotating recommendations

User requested a smaller top card so club cards start in the initial viewport, plus
another sport-specific recommendation that changes smoothly after a reading interval.

- Target roughly 210–240 pt for the hero including controls at standard text size.
  Large accessibility text takes the space it needs, without fixed-height clipping.
- Search stays first. A second card offers an individual training session for the
  first eligible sport selected in the profile with a nonempty club section.
- UI eligibility: tennis, table tennis, padel, squash, badminton, fitness, boxing,
  yoga. This is a recommendation scope, not a restriction on PersonalActivity.
- Copy asks users to choose a club and check session arrangements. It does not
  claim a coach, a free slot, equipment or an available booking. The CTA reuses
  the sport-filtered club catalog and existing club/visit flow.
- Eight seconds is an initial product hypothesis, not an established psychological
  optimum. Manual controls and pause/resume remain available; interaction stops
  automatic switching until explicitly resumed. Offscreen/inactive states pause it.
- Reduce Motion and VoiceOver use manual navigation. An ineligible profile has one
  card, without autoplay or redundant controls. Inactive content is not interactive
  or exposed to accessibility.
- Motion controls follow the principle described by
  [W3C WAI carousel guidance](https://www.w3.org/WAI/tutorials/carousels/animations/).

### Follow-up verification

- Final required iOS build: **BUILD SUCCEEDED**, log
  `.artifacts/ios-empty-deck/xcodebuild-carousel-verified.log`.
- Compiled current production eligibility/autoplay/visibility functions in an isolated
  Swift checker: **31 assertions passed** (sport selection, profile order, missing
  supply, all autoplay vetoes and the visibility threshold).
- `git diff --check`: passed. No API or database changes. Web/Prisma checks are not
  relevant to this native UI change; no iOS automated test target exists.
- Actual production view compiled in the Simulator fixture host. Clean screenshots
  `compact-search.png` and `compact-training.png` confirm both recommendation pages,
  automatic advance, stable hero height and a fully visible first club card at
  standard text size on iPhone 17 Pro (402 pt wide), with a Discover-sized header
  and bottom navigation inset. Fixtures are illustrative clubs, not live data.
- Inspected `carousel-large.png` (EN accessibility3): hero text and CTA are not
  clipped. `carousel-unselected.png` confirms a single card without carousel controls
  when the profile has no eligible sport.
- Independent final QA: **PASS within the verified scope**, no blocking findings.
- Runtime diagnosis caught a zero-frame PreferenceKey delivery bug; direct geometry
  appearance/change observation fixed it. A timed debug run advanced to training
  after nine seconds with the same 370 × 208 pt hero frame; debug code is confined
  to ignored artifacts and is not part of the app.
- Manual pause/resume, page taps and scroll-out/back were reviewed in source and
  gate assertions, but could not be repeated through native UI automation: Simulator
  accessibility actions returned invalid elements and its screenshot API was unavailable.
  The earlier original-design navigation/share checks remain documented above.

### Follow-up residual risks

- Eight seconds remains a starting product hypothesis; measure engagement before
  changing the interval. This is no claim of a psychological optimum.
- The card uses profile sport order and existing nonempty club sections; player/club
  ranking scores are unchanged. Club data does not guarantee individual training,
  so the CTA asks users to check arrangements. Missing club sections can suppress
  a useful recommendation; incomplete club sport metadata can include unsuitable clubs.
- Before release, smoke-test pause/resume, manual paging, scrolling and VoiceOver
  on a physical iPhone. Preview checks do not cover live bookings/search submission.
- Concurrent activity-feed changes in app/project/navigation files belong to another
  task and were neither edited nor reverted here.

## Follow-up: restore court and ball artwork

User explicitly wants the original court-and-ball illustration retained. Restore
its native vector appearance inside the compact recommendation header. Keep the
current card height and initial club visibility, readable text, existing carousel
controls and their touch areas. Decorative artwork must be accessibility-hidden
and must not intercept taps. No selection, ranking, API or data changes.

Frontend/Mobile owns the visual edit; Orchestrator performs final target build and
Simulator screenshot review. Existing product/architecture acceptance criteria
remain applicable. This reversible decorative change needs no new logic tests.

Artwork verification: final iOS target build **BUILD SUCCEEDED** (log
`.artifacts/ios-empty-deck/xcodebuild-artwork.log`); `git diff --check` passed.
The production-view Simulator screenshot `compact-artwork.png` confirms readable
court/ball artwork, unchanged two-slide card height and a fully visible first club.
Only `EmptyDeckView.swift` and this packet changed for the correction. Existing
manual-gesture/live-account verification limits remain; no new domain risks.
Single-slide screenshot `artwork-single.png` also confirms the first club remains
fully visible. Independent final QA: **PASS**, no blocking findings.
