# Default-on player map and registration explanation

## Request and approved behavior

The user changed the previous default-off decision: map visibility should be enabled by default, registration should explain that players see each other in their convenient play areas and can disable it in settings. The user then explicitly requested enabling existing accounts too.

This packet supersedes default-off rollout guidance in `task-packet-district-player-map.md`. The underlying district map, sports filtering and safe public projection remain unchanged.

- New database accounts default to `showOnMap=true`.
- Existing accounts, including stored false values, are enabled once by an explicitly authorized rollout migration. A durable migration marker and transaction prevent retries/concurrent runs from overwriting later opt-outs.
- New/legacy guest drafts default to true; an explicitly saved false survives draft reload.
- Registration exposes an editable map switch and explains shared preferred play areas, whole-city fallback, and disabling in settings. It is separate from the legal agreement and from looking for a game.
- Profile completion carries the draft choice, but cannot re-enable a returning incomplete account that has since saved false. Normal logins and PATCH omission preserve the stored flag.
- Email/Apple authentication accepts an optional boolean preference, used only in the account creation branch. This preserves an immediate registration opt-out even when the user has not entered profile details. Returning-account login ignores that request preference and retains its stored choice. Existing native main-screen routing is preserved.
- Missing flag/area fields in authenticated/public API responses still decode as false/empty. The client must not infer visibility from a missing response field.

## Ownership and scope

Product/Architect reviewed entrypoints and froze the contract before implementation. Backend/Web owns schema, migration, auth/onboarding forms/draft logic and server tests; Mobile owns native guest draft, onboarding presentation and profile promotion; Root owns baseline preservation, this packet, integration and required checks; Architect performs independent final QA.

Current working-tree source is snapshotted in `/tmp/tennis-map-default-on-baseline/source.zip` with hashes. Specialists work on disjoint files in the main working directory and preserve existing changes.

Affected domains: profile visibility and registration, preferred district explanation. Unchanged: sport levels, area membership, availability, game/search lifecycle, matching/ranking, chat, notifications, reliability and premium.

## Acceptance and checks

Verify default-on for email/Apple account creation; visible switch and explanation; draft false roundtrip/promotion; completed and incomplete returning-account false preservation; old PATCH omission; one-time enable-existing migration, default true, atomic failure and repeat/concurrent execution; both historical initializer + followup and direct fresh followup; unchanged public missing-field fallback and district privacy tests.

Required: Prisma generation, lint, full tests, production web build, native simulator build and meaningful draft/promotion checks. Database verification uses only a temporary isolated synthetic database. No production deployment or TestFlight upload is included.

## Validation and residual risks

Implementation complete; all required automated checks passed.

Independent final QA: PASS, no blocking defects found. Creation-only preferences, returning-user preservation, promotion, missing-field defaults, migration atomicity and source/build correspondence were reviewed.

- Prisma generation: PASS, generated client only.
- Lint: PASS (`/tmp/map-default-on-lint.log`).
- Full tests: PASS, 518 tests / 75 files (`/tmp/map-default-on-tests.log`).
- Production web build: PASS in an isolated frozen copy (`/tmp/map-default-on-build-isolated.log`). The first root build collided with a concurrently running development server's `.next` output and failed with missing generated pages; the server was left running. All 424 copied build source files matched the root after successful isolated compilation.
- Native actual-source checks: 27/27 PASS. `/tmp/check-native-map-onboarding.py` extracts draft encoding/decoding, the unchanged authenticated-model fallback, auth request encoding and the profile promotion method, including saved media/settings preservation.
- Native Debug simulator build: PASS (`/tmp/map-default-on-ios-build.log`). Uses the preserved 91-file baseline plus the six native task files, because another task concurrently edits CourtsView. That unrelated source remains untouched; its in-progress behavior is outside this verification.
- Final source verification: all 424 web snapshot files, all six native task files and the migration SQL hash match the verified versions. Final whitespace validation passed.

Changed areas: Prisma default and deployment marker, one-time SQL rollout, email/Apple creation contracts, web guest draft/registration/profile switch and translations, native guest draft/auth requests/onboarding/profile promotion, and regression tests. Ranking and map area membership did not change.

PostgreSQL 16 rollout verification: 14/14 PASS in a temporary network-isolated container containing only a synthetic User table. Covered historical initializer upgrade, default-on new rows, direct missing-column application, one marker, later opt-out preservation on sequential/concurrent retries, and forced failure rolling back the flag/default/marker followed by a successful retry. Container removed. SQL SHA256: `24d60ffaba2e4999bc6f9572bf21eb66d9295456f5da064aa7e265aa71b7eec2`; logs `/tmp/map-default-migration-qa.log` and `.json`.

CUA access to Simulator again returned timeout `-10005` during this task. Onboarding visual layout and interactions require a manual device/simulator check, as do the earlier map gestures. Existing old clients do not implement the new map contract. Region display and this product preference are not a legal compliance certification; no legal agreement acceptance is inferred from the enabled default.

Production and TestFlight have not been updated for this task. The one-time enablement for existing accounts is prepared, not applied to production. Follow the ordered rollout in `deploy/migrations/20260906-player-map-visibility.md`; retain the DeploymentMigration marker so future opt-outs are not reset by retries.
