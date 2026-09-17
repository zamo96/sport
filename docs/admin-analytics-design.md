# Operational analytics: registration to first game

## Ownership and data contract

`src/server/admin-analytics.ts` provides aggregates and a bounded event journal to `/admin/analytics`; shared display types, filter normalization and CSV formatting live in `src/lib/admin-analytics.ts`. `GET /api/admin/analytics/export` authorizes administrators before accessing data. The existing `UserEvent` table and indexes are reused; no migration or external service is required. Web and iOS retain existing API contracts.

The global period is 7, 30 or 90 UTC calendar days, including the current partial day. User ID and event type filter only the journal and export, not the overview or cohort. Journal pages contain 50 rows ordered by timestamp and ID. SQL aggregates return bounded daily, event-type and funnel results; the service does not fetch all raw events into memory. CSV uses the same journal filters, limits output to 10,000 events and includes a visible truncation row plus a response header and filename suffix when truncated. All cells are quoted; spreadsheet formula prefixes are escaped.

## Sources of truth and conversion

The registration cohort uses `User.createdAt` during the selected period. Direct registration-to-game conversion divides cohort users with a valid first-ever played game by all cohort registrations, observing results through the current time. It does not require telemetry intermediates. This is an open cohort: recent users have had less time to convert. It is not a fixed 7-day activation rate.

Played games require current `GameRequest.status = accepted`, `outcome = played`, a non-null `outcomeUpdatedAt`, and no disputed report on that request or its shared root. The date is the time of marking the result, not the scheduled game time. An accepted shared invitation with no explicit outcome inherits its accepted root’s played outcome and timestamp, because the report route updates only the root. An explicit child `not_played` outcome blocks inheritance. Each qualifying request attributes participation only to its creator and matched user; declined invitations never inherit a result. Shared root IDs deduplicate game counts; a game can be the first for both players. Each user's first game is the earliest valid result across their full history. Reversals and later disputes can change historical metrics. Photo reports currently auto-confirm participants, so the interface must describe games as marked played in the app rather than independently verified.

The strict observed funnel is registration → `profile_completed` → positive intent → `request_accepted` → authoritative first game. Positive intent comprises `search_created`, `search_response`, `request_created`, or `swipe` with `context.action` equal to `like` or `superlike`. Each timestamp must be at or after the previous step, using the earliest qualifying event after that step. Users receiving invitations without initiating search may convert outside this funnel; the direct outcome metric still counts them. Missing historic events cannot be inferred from a profile's current state. Client events cannot supply server-only milestones.

Daily first games counts users whose first-ever valid result falls on that day, across all registration dates. Daily active users counts distinct actors with recorded events, excluding passive push delivery/conversion, match creation and game acceptance/completion event types that may be emitted for multiple participants. It is observed activity, not a backfilled historical DAU series.

## Coverage and limitations

The earliest available event and earliest available funnel milestone are displayed separately. Neither proves the deployment start, and no events are backfilled. Server action instrumentation covers API consumers including web and iOS. Web screen views are additional telemetry; native screen views and anonymous visits are outside this delivery. There is no acquisition-channel attribution, session replay, full request-error database or fixed-window retention model. Existing operational dashboards remain available for integrations, reports and maintenance.

SQL parameters use Prisma tagged templates. Event journal and CSV include account identification for authorized operators; event payloads should use bounded technical metadata and avoid messages, auth codes, exact location and unrestricted text. Telemetry remains best effort and must not fail the user's action. Since user events cascade on account deletion, this is an operational database rather than an immutable warehouse.

At substantially greater scale, the repeated first-game domain aggregation may benefit from a maintained fact table or materialized view with outcome-reversal handling. Such schema and retention decisions are separate work. Current queries aggregate in PostgreSQL and bound all returned detail data.

## Acceptance checks

Verify empty cohorts, zero denominators, ordered and repeated steps, pre-observation users, rejected and disputed games, reversals, shared invitations, first-ever game dates, journal pagination/filter parity, UTC boundaries, admin denial before queries, CSV formula escaping, and visible export truncation. Required repository lint/tests/build run after integration. No ranking inputs, recommendation eligibility, premium rules or client API response contracts change.
