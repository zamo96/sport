# Production player map enablement

## Authorization and initial state

The user explicitly requested enabling production players on the map using their saved city/district preferences. Earlier instructions authorized a default-on policy and a one-time enablement of existing accounts. Subsequent user opt-outs must be preserved.

The current TestFlight **1.2 (2026090603)** already includes the new map-area client. Before this deployment, production ran `20260906-profile-status`, image `sha256:d4f920ae8f60f958909901f6c50df581c65ca1f260f507d1a9f406f5e2b87a3f`, without the `showOnMap` column or DeploymentMigration table. Missing map fields hid players in the updated client. No new native upload was required to add the server contract to that build.

Read-only initial database audit: 27 users, 18 with a saved city or canonical place, 19 completed active profiles, 9 null district selections. Geography and preference values are not rewritten by this release. A visible flag without a usable city does not invent a map point.

## Release scope and ownership

The candidate at `/tmp/tennis-prod-player-map` starts from **409 source/config/test files verified against the actual deployed release**; `.artifacts/admin-profile-status/overlay` matched every hash. The main dirty working tree is not used as a wholesale release source.

Backend/Web specialist owns a selective map overlay: schema and one-time rollout scripts; optional creation/profile preference; safe public area and nested-user projections; required candidate selections; a web registration/profile setting with compact info disclosure; focused regressions. Existing production analytics, admin profile status, onboarding rules, matching and media behavior remain the baseline. Unshipped nearby, Android and unrelated native/web work is outside this release.

Root owns source verification, full checks, image staging, database backup, one-time SQL application, guarded activation/rollback and live smoke checks. Architect performs independent pre-deployment and final QA. Ranking formulas and eligibility do not change.

## Deployment invariants

- Backup stays on the production host with restricted permissions; secrets and user records are not downloaded or logged.
- Build and review the candidate before applying SQL. Verify the expected active image before any activation.
- Apply the additive column initializer followed by the tested atomic default-on rollout. The durable marker prevents reruns from resetting a later opt-out; retain the marker during application rollback.
- Existing users are enabled once, as authorized. Their saved districts/city and private home coordinates are preserved. Null or empty preferences produce all districts of the saved city; no district coverage produces a shared city point.
- Never run the seed, manually blanket-update visibility after the marker, or change production accounts to create a test scenario.
- Replace only the app container; preserve database, Redis, nginx and production configuration. Retain a known previous-image rollback.
- Verify health/readiness, guest discover map contracts, canonical public coordinates and authentication protection. No new production test accounts, swipes, matches or notifications.

## Status

Candidate checks passed: **501 tests / 72 files**, lint, Prisma generation and final local production build. All **420 release-source hashes** match the frozen candidate, with 26 map-only changed/new files. Independent source review passed. The archive SHA256 is `321a960f7f2c09578ea58b3bd72c56a48ee9a143e820a7008f2b343339e49126`; source/overlay manifests and deployment scripts are retained in `.artifacts/player-map-release/`.

Pre-release public guest discovery returned 12 candidates, zero `showOnMap`/`mapAreas` contracts and zero public map areas. Only aggregates and an ordered-ID digest were retained. Native Python's CA configuration failed the initial HTTPS probe; a standard certificate-validating curl probe succeeded, without bypassing TLS checks.

**Deployed successfully on 2026-09-06.** Production now runs `tennis-search-app:20260906-player-map`, immutable image `sha256:38b44d64eb90a401fb812019530fabc57c6878d7f244daee8af8f6bffd27d1a2`. Remote image source verification passed for all 339 packaged source/config files. Stage and activation both exited 0; an independent post-activation inspection confirmed that exact image is healthy.

The database backup was created and its archive listing validated before either SQL script ran; it remains on the production host, with its path recorded in the release evidence. The one-time rollout enabled all 27 existing accounts. Read-only verification confirmed the column is non-nullable with default `true` and exactly one durable rollout marker. Subsequent opt-outs are preserved by migration reruns.

Live checks passed: 18 accounts have usable canonical map areas, all 18 are active, verified and completed. Guest discovery returned 12 candidates with 12 map-area contracts and 12 nonempty area lists, compared with zero before deployment. Every returned area's coordinates matched the canonical helper applied to its stored preferences. Recursive checks found none of the prohibited private fields in the public response. A separate certificate-validating public HTTPS probe confirmed all 12 contracts/area lists again. Ordered-candidate digests differed between probes; ordering stability is not claimed from this smoke test. Source review and regression tests confirm no ranking formula or eligibility changes.

Local and public health/readiness passed; unauthenticated profile and analytics-export endpoints remained protected (401). Database and Redis container IDs and nginx configuration were unchanged. The previous immutable app image remains tagged for rollback; additive schema and the durable marker must be retained during rollback. The rollback script explicitly checks both container replacement success and the exact previous image before reporting restored readiness.

Evidence is retained in `.artifacts/player-map-release/`: source manifests, deployment scripts, stage/activation logs and exit codes, image identities, aggregate live checks, database contract metadata and public before/after probes. No production secrets, user rows or database backup were downloaded.

Independent architect/QA closure: **PASS**, no blockers. Successful activation, image identity, default-on semantics, live map contracts and documented limits were reviewed after deployment.

## Remaining limits

- This deployment changes backend/web only. No native files changed and no new TestFlight build was uploaded; use TestFlight 1.2 (2026090603) and reopen the app to fetch fresh player data.
- Nine accounts have no usable canonical city and therefore receive no invented map location, even though the visibility preference is enabled.
- Server/public API behavior is verified against live production. A visual check on a physical iPhone was not performed as part of this deployment.
