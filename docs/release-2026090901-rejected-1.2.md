# TestFlight 1.2 (2026090901)

User explicitly authorized releasing the notifications navigation correction. Delivery follows the existing TestFlight workflow; no public App Store submission or backend deployment. The actual production hang is not yet proven resolved; the release contains a targeted correction of a confirmed source-screen lifecycle gap.

## Scope and ownership

Root owns freezing, builds, signing, upload and reporting. Independent release_qa reviews the frozen source, checks and distribution artifacts. Acceptance: app/widget version 1.2 build 2026090901, HTTPS sportsearch.shop, mocks NO, debug trust NO, production APNS, valid App Store distribution signatures/profiles, source hashes unchanged, native checks and builds pass, Apple upload outcome recorded.

Source baseline is the latest uploaded TestFlight 1.2 (2026090604), frozen under `build/TestFlight/source-1.2-2026090604`. Unrelated working-tree chat/read-receipt and other changes are excluded. Candidate snapshot `build/TestFlight/source-1.2-2026090901` includes exactly 97 files; full hashes and the two-file delta are in `build/TestFlight/release-2026090901-manifest.json`.

Changes from 0604:

- `ios/TennisSearchIOS/Views/DiscoverView.swift`: explicit notifications presentation state and navigation destination; cancel auto-advance before push, gate source geometry/playback during presentation, add bell accessibility label/identifier.
- `ios/TennisSearchIOS.xcodeproj/project.pbxproj`: four app/widget build settings advance to 2026090901. Marketing version remains 1.2.

No notification data, seen/badge behavior, destination routing, backend, schema or API contract changes. Profile, sport/levels, location, availability, game/proposal/search lifecycle, ranking, chat unread semantics, push registration, reliability and premium rules are unchanged.

## Prior local validation and limitations

Local candidate simulator build and 68 adjacent native assertions passed. Five normal bell/open/back cycles and group collapse/expand passed using mock data on iOS 26.3.1. No successful physical hang capture; connected phone was iOS 18.7.8 with 1.2 (2026090603). Scroll, edge-swipe/cancelled pop, empty/one/30-row payloads, delayed/offline refresh and account-specific reproduction remain unverified. These limitations are disclosed; do not describe the production incident as definitively fixed.

## Release validation

- Frozen Release archive: PASS (`build/TestFlight/archive-1.2-2026090901.log`).
- Frozen Debug arm64 simulator build: PASS (`build/TestFlight/simulator-1.2-2026090901.log`).
- Fresh actual-source checks from the snapshot: 39 auto-advance + 84 player-map + 36 required-onboarding assertions = 159 PASS, process exit 0.
- Archive metadata, strict signatures and 97/97 frozen hashes: PASS (`build/TestFlight/verification-1.2-2026090901.json`). Both app/widget use 1.2 (2026090901), HTTPS sportsearch.shop. Main app mocks/debug trust NO and configured APNS production.
- Local App Store export: PASS (`build/TestFlight/local-export-1.2-2026090901.log`), IPA `build/TestFlight/export-1.2-2026090901-local/Sportia.ipa`.
- Independent distribution artifact verification: PASS (`build/TestFlight/distribution-verification-1.2-2026090901.json`). Actual app/widget have Apple Distribution signatures, team M2ZZ39HQZ5, matching App Store profile/certificate identifiers with expiry 2027-05-13, get-task-allow false, main APNS production, and executable UUIDs matching archive and dSYM. Local IPA SHA-256: `cbf1f9b06162066b26c732a6b59fa8cc0a9c14be5586e2d96088c1d501b81a1b`.
- Npm/Prisma checks are not applicable to this isolated native release. Existing ProfileView warnings about AVAsset.duration and Sendable capture are unchanged; no build errors.


Apple rejected this version: train 1.2 is closed and CFBundleShortVersionString must exceed the approved 1.2. Upload log `build/TestFlight/upload-1.2-2026090901.log`, exit 70. No build accepted. Superseded by 1.2.1 (2026090901); see release-2026090901.md.
