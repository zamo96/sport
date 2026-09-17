# Training push navigation server error — 2026-09-10

## Scope and evidence

User reports opening «Не хотите сходить на тренировку?» and seeing «Что-то пошло не так» in iOS. Production at 07:02:39 UTC returned HTTP 400 for `GET /game-searches/my`, correlated with a Prisma `RegularPairOccurrenceConfirmation.upsert` uniqueness failure on `(occurrenceId, userId)`.

The released iOS 1.2.1 (2026090901) correctly handles `/play/searches/new?day=friday&time=evening&sport=tennis` as a prefilled composer. Opening the searches area also fetches `/game-searches/my`, whose regular-pair synchronization can run concurrently with other read endpoints. The client classifies the resulting internal database error as the reported generic server error.

## Requirements and technical decision

Create missing occurrence confirmations atomically. Concurrent synchronization must succeed without duplicate confirmations, preserve existing confirmed/declined answers and response times, restore a missing participant, and propagate unrelated database failures. Replace the two empty-update Prisma upserts with one `createMany` using `skipDuplicates: true`. PostgreSQL remains the source of truth for uniqueness.

Backend specialist owns `src/server/regular-occurrences.ts` and `tests/regular-occurrences.test.ts`; mobile specialist verifies frozen release routing without changing client code; independent QA reviews acceptance; orchestrator owns integration, release, and this packet.

Affected domain: regular game occurrence confirmation lifecycle, reached from a notification into game search. Notification copy, campaign targeting/caps, push devices, scheduling rules, profile, sport levels, location, availability preferences, discovery/ranking, chat/unread state, cancellations/no-show/reliability, and premium behavior are unchanged. No schema, migration, API contract, or iOS change.

## Verification and rollout

- Local `npm run lint`: PASS.
- Local `npm run test` with Node 22: PASS, 81 files / 599 tests, including four new regression cases.
- Local `npm run build` with Node 22: PASS.
- Frozen iOS routing and error classification: nine assertions PASS using synthetic inputs and released source.
- Independent scoped QA review: PASS.
- Actual local PostgreSQL: legacy empty-update upsert reproduced 31 `P2002` errors in a 32-way concurrent trial, on the production constraint. Patched service: 24 concurrent synchronizations, zero errors, exactly two confirmations per scheduled slot. Another 48 concurrent synchronizations preserved confirmed/declined answers, `respondedAt`, and `updatedAt`, and restored a missing participant. Transaction-client execution passed. The isolated scratch schema was dropped and its removal verified.

Deployment uses an exact copy of active production release `20260909-phantom-invites`, with only the service file and image tag changed. The service's pre-edit SHA256 matches production: `42f70933a036baadc8dc0a9a29da7de45461709128eaaf3eb4e82083ca8ddee9`; patched hash: `0045fff4da72191f1e7438c06b692de438ff7e2e98f54122c3d6e2258be7bf66`. No unrelated working-tree changes are deployed. New release: `20260910-occurrence-confirmations`.

The original Docker build was blocked by expired `bullseye-security` repository metadata before application build. Release-local `Dockerfile.hotfix` instead uses the exact active application image `sha256:2378503c823f56cd376c21090d92c2b65753a57455d768582a28dd8354f6c99f` as builder and runner, rebuilds Next.js against copied production source, and overlays only `.next` and `src` in the final image. This preserves the existing runtime and dependencies. The original Dockerfile is unchanged; general runtime maintenance is separate.

## Production result

Activated successfully at **2026-09-10 07:19:29 UTC / 10:19:29 MSK**. Image: `sha256:dbc448b0c68a8daa970f3300e4da653f5e57b17e8b61ca8fa94c2c943853c49b`. Exact production-source build including lint/type checks passed. Packaged service hash verified before activation. Only application container recreated; database/Redis container IDs, runtime environment, and mounts unchanged. Lifecycle campaigns remain enabled. Internal and public `/health` and `/ready` all returned HTTP 200. Previous release/image retained for rollback. Server-side audit: `/opt/tennis-search/releases/20260910-occurrence-confirmations/activation-audit.json`.

Residual scope: this addresses the confirmed server uniqueness error. The earlier separate iOS bell-screen hang/layout investigation remains independent. A physical-device retap is not part of the automated checks.
