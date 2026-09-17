# Onboarding and sign-in release

User explicitly authorized uploading the completed changes to TestFlight and deploying the backend if necessary. The requested marketing version is **1.2** for both the app and widget.

## Release scope and ownership

- iOS release owner freezes the current verified native sources, bumps the app and widget build number, creates a production Release archive, and validates its configuration/signature. Retain completed native work in the workspace, including temporary activity-feed hiding; enumerate differences from the preceding TestFlight manifest.
- Backend owner audits the live production baseline and compatibility. Prepare only a scoped candidate for these web/onboarding changes if production deployment is needed. Do not deploy the entire dirty working directory or include unrelated schema/server changes.
- Orchestrator coordinates the release and final upload/deployment; independent QA validates candidate source manifests, required-field fixes, absence of the auth map control, production configuration, and check results before publication.

## Acceptance

- The uploaded iOS app and widget have matching fresh version/build metadata and valid distribution signatures.
- API target is HTTPS sportsearch.shop, mocks/debug trust are disabled, and APNS uses production.
- Native source manifest is unchanged throughout archive creation; required onboarding and auth-map changes are included.
- Apple upload reports successful acceptance; processing and tester availability are distinguished in the report.
- Backend necessity and compatibility are explicitly documented. Any deployed overlay preserves existing production behavior and configuration, has passing scoped/full checks, an image rollback, and post-deploy health/readiness verification.
- No production test users, notifications, account changes, destructive data migrations, or public App Store submission are needed.

## Status

Version **1.2 (2026090603)** was accepted by Apple at **2026-09-06 19:32:41 Moscow time**. Upload exited 0 and reported successful upload / package processing. Tester-group availability remains unconfirmed. No public App Store submission was performed. Details: `docs/release-2026090603.md`.

Final native checks: archive and simulator builds PASS, 36 onboarding plus 39 auto-advance assertions PASS, all 95 frozen source hashes match, app/widget versions and distribution signatures PASS, production API/APNS and disabled debug/mocks verified. Independent release QA PASS before upload. Prior web lint/build and 561 tests, and Android build and 8 tests, passed; Android publication is outside this request.

Read-only production audit confirmed the active healthy `20260906-profile-status` release already enforces supported sports and a resolvable city/place in `/me`. These native onboarding fixes require no server or schema update. Unrelated local map/schema features are not part of the release; no backend deployment is planned. Web corrections remain local in this native release.
