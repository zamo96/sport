# Photo upload limit: 20 MiB

User wants the visible 5 MB photo limit increased. Product/Architect froze 20 MiB per photo, inclusive, with a shared browser-safe constant and consistent errors/hints. This follows the authorized release request: deploy backend changes to Yandex Cloud production after validation; the existing iOS TestFlight build consumes the same live API and needs no rebuild.

## Scope and ownership

Backend specialist owns shared upload limits, generic and chat image validation, streamed multipart limits, route checks, nginx template and regression tests. Web specialist owns existing upload hints/client preflight. Root owns deployment discovery, checks, release and this packet. Architect performs independent final QA after required checks. Preserve all unrelated native work and release artifacts.

Applies to avatars, profile photos, club photos, game-report and personal-activity photos, and chat photos. Keep existing formats, video 60 MiB, chat 40 million pixel limit, four attachments, frequency limits, authorization and sequential normalization. No schema or API shape changes; no recommendation, sport, geography, availability, game/search lifecycle, reliability, notifications or premium changes. Profile/chat/report media acceptance changes only.

## Acceptance and checks

- One shared 20 MiB limit drives server validation and web hint text.
- Valid images above the former 5 MiB limit and at exactly 20 MiB are accepted; 20 MiB + 1 byte is rejected with the new limit.
- Chat multipart accepts the inclusive boundary, enforces file/count/request caps with or without Content-Length and stops failed streams without hanging.
- Preserve malformed-image/MIME/pixel protections, attachment counts and video behavior.
- Retain nginx's general 10 MiB cap and allow a bounded 85 MiB request under /uploads/ for four 20 MiB images plus multipart overhead. Inspect the actual production proxy before changing it.
- Run relevant targeted tests, npm lint, npm test and npm build, then independent review. Prisma generation occurs in the normal build; no migration is required. No native source changes mean no extra TestFlight build.

Memory per allowed photo/batch rises; retain sequential normalization. Generic formData buffering is existing behavior and a full streaming rewrite is outside this increment.

## Verification and deployment preparation

- Implemented shared `src/lib/upload-limits.ts`, generic photo validation, chat detection/normalization/route errors and bounded multipart cancellation. Web report, chat and avatar surfaces use the same limit for hints/preflight. The nginx template grants 85m only to `^~ /uploads/`.
- Targeted tests: 31/31 PASS, including a real 6 MiB JPEG, inclusive 20 MiB boundaries, +1 byte rejection, stream cancellation without Content-Length and unchanged format/pixel/video rules.
- Required checks: `npm run lint` PASS with no warnings/errors (`/tmp/photo20-lint.log`); `npm run test` PASS, 58 files/373 tests (`/tmp/photo20-test.log`); `npm run build` PASS including Prisma generation (`/tmp/photo20-build.log`). Scoped whitespace PASS. Independent static QA PASS.
- Existing iOS code has no 5 MiB limit and sends photos to the live upload endpoints, so this increment does not alter native files or require another TestFlight upload.
- Production discovery: current container points to `/opt/tennis-search/releases/9d28e10`; all eight changed existing backend/web/template files match git 9d28e10 exactly. This prevents overwriting unknown server-side edits. Existing app, Postgres and Redis were healthy before deployment. Actual TLS nginx configuration had a global 10m cap.
- Prepared isolated source release `/opt/tennis-search/releases/20260905-photo20` from 427 web/backend source files, including the new helper/tests. Source hashes independently verified against `/tmp/tennis-photo20-source-manifest.json`. Production environment copied only within the server; local credentials, native artifacts and local environment files were excluded from the uploaded source archive.
- Preserved old image as `tennis-search-app:rollback-20260905-photo20`. Prepared nginx candidate from the live configuration, adding only the uploads location while preserving TLS/redirects. Activation script requires the expected previous image and unchanged nginx file, replaces only app, waits for health, validates/reloads nginx and restores the previous app/configuration if activation fails.
- Runtime smoke plan uses an isolated local-only temporary directory in the new image, without database, S3 or user changes. Public proxy verification uses unauthenticated requests: a body above 20 MiB must reach the app and return 401; other routes above 10 MiB and uploads above 85 MiB must still return 413.

## Production result

- Docker image build PASS on the production host. Built image `sha256:c7bb936f13aa23a51e06951513d92a8a9b1ff708e37bdd49797273bebdae32fd`, tagged `tennis-search-app:20260905-photo20`.
- Isolated image smoke PASS, 16/16 checks, with networking disabled and local temporary storage only. Verified 20 MiB acceptance, +1 byte rejection, real JPEG above 5 MiB decoding/normalization and local stored bytes. No S3, database or user account was touched by these checks.
- Deployment PASS: app-only replacement from the isolated release, matching explicit image tag, healthy container and HTTP health responses; nginx configuration test PASS and reload successful. TLS/redirects preserved. App labels confirm active release directory `/opt/tennis-search/releases/20260905-photo20` and the tested image digest.
- Public HTTPS proxy smoke PASS: body above 20 MiB under `/uploads/avatar` reaches the app's authorization gate (401), an 11 MiB non-upload request remains 413, and an 86 MiB upload request remains 413. This tests ingress boundaries without claiming an authenticated S3/account upload.
- Production Postgres and Redis stayed running; no schema migration, data mutation or restart of those services was performed. Previous application image and nginx configuration are retained for rollback.
- Evidence logs copied locally: `/tmp/photo20-deploy.log`, `/tmp/photo20-image-smoke.log`, `/tmp/photo20-proxy-smoke.log`. Final source/build QA and deployment-script review passed. Existing TestFlight 1.1 (2026090501) receives the new server limit without another upload.
- Remaining limitation: no real-user authenticated S3 upload was performed during verification; storage integration itself was unchanged. Higher permitted batch memory and existing generic multipart buffering remain as documented above.
