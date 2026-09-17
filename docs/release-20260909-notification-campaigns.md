# Production notification campaigns — 2026-09-09

User authorized enabling the existing notification campaigns. This is a production configuration change only, covering all seven campaigns behind `LIFECYCLE_CAMPAIGNS_ENABLED`. No application source, schema, targeting rules, ranking, clients, or notification copy was deployed.

## Acceptance and ownership

Orchestrator performed production inspection and activation; an independent QA agent reviewed dry-run safety and activation requirements. Acceptance: preview without sending, persist the switch, retain the exact running image and other environment variables, recreate only the app, preserve database/Redis containers, verify runtime state and health.

## Evidence

- Before activation: running and persistent switch `false`; cron schedule `*/5 * * * *`, recent invocations confirmed in the server journal. Four historical campaign records, all urgent digests from July 7–8; no recent campaign records.
- Production source hashes matched local reviewed sources for notification-campaigns, lifecycle-campaigns, hot-search-digest, and notification translations.
- Pre-activation dry-run returned HTTP 200, `success=true`, `dryRun=true`, no sends or failures. Game maintenance was skipped. Current quiet hours and targeting rules remained enforced.
- At 19:05 UTC / 22:05 Moscow, changed only `LIFECYCLE_CAMPAIGNS_ENABLED=false` to `true` in the active release `.env.production`. Compose configuration and runtime environment were compared to the original; no other environment differences.
- Recreated only the application with `--no-deps --no-build --pull never`, retaining image `sha256:38b44d64eb90a401fb812019530fabc57c6878d7f244daee8af8f6bffd27d1a2` (`tennis-search-app:20260906-player-map`). Database and Redis container IDs unchanged.
- At 19:05:45 UTC, application healthy; internal and public `/health` and `/ready` all HTTP 200. Persistent and runtime switches both `true`.
- Post-activation dry-run HTTP 200, successful, zero sends/failures. No live campaign invocation was triggered manually; existing cron controls dispatch.
- Source lint/tests/build, Prisma generation and iOS build are not relevant to this configuration-only activation. Prior copy change remains local.
- Independent QA final decision: PASS against the activation evidence; future campaign delivery remains unverified.

## Operations and limitations

Active release: `/opt/tennis-search/releases/20260906-player-map`.

Server-only configuration backup: `.env.production.before-campaigns-20260909T190521Z`; activation audit: `campaign-activation-20260909T190521Z.json`. Credentials remained on the server and were not included in this report.

Rollback: restore the prior switch (`false`) and recreate only the application through the same production/release Compose files, with the same image and no dependency recreation.

Quiet hours are 22:00–09:00 per user timezone; Moscow users will only become eligible after 09:00, subject to other filters and caps. Zero previews tonight do not establish tomorrow's audience. Real device receipt and future conversions have not yet been verified. Standard campaign limits are 1/24h and 3/7d; urgent digest thresholds are 2/24h and 10/7d, using shared campaign delivery counts.
