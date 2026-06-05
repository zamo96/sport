# Railway Production Rollout

## Decision

Use Railway as the first production platform:

- Railway service for the Next.js app container.
- Railway managed PostgreSQL for production data.
- Separate Railway environments for `staging` and `production`.
- Object storage outside the app container for uploaded avatars.
- Synthetic user simulation as a release gate before public traffic.

This is the right first production shape because the repo already has a Dockerfile, Prisma, and a PostgreSQL-first data model.

## Release Stages

1. `local hardening`
   - replace production startup schema mutation with migrations
   - add health/readiness endpoints
   - move avatar uploads out of `public/uploads`
   - add production-safe auth rate limits

2. `staging on Railway`
   - create Railway project and staging environment
   - provision staging Postgres
   - deploy the Docker image from the main branch
   - run migrations with `prisma migrate deploy`
   - run synthetic agents against staging

3. `closed beta`
   - create production Railway environment
   - restore or migrate only approved seed/reference data
   - enable monitoring and error alerts
   - invite a small controlled group
   - review synthetic traffic and real user traces daily

4. `public launch`
   - freeze schema changes during launch window
   - keep rollback target ready
   - monitor auth, discover, game search, messages, and database latency

## Required Code Changes Before Production

- `package.json`: production `start` must not run `prisma db push`.
- Prisma: introduce committed migrations and use `prisma migrate deploy` for Railway release phase.
- Uploads: replace local `public/uploads` writes with S3-compatible storage such as Cloudflare R2.
- Auth: add rate limiting for OTP request and verification attempts.
- Observability: add Sentry or equivalent error tracking.
- Health checks: add liveness and readiness endpoints. Readiness must verify database access.
- CI: add a required pipeline for `npm run lint`, `npm run test`, and `npm run build`.

## Railway Environment Variables

Required:

- `DATABASE_URL`
- `NODE_ENV=production`
- `NEXT_PUBLIC_MAP_PROVIDER`
- `NEXT_PUBLIC_YANDEX_MAPS_API_KEY`

Recommended:

- `SENTRY_DSN`
- `UPLOADS_BUCKET`
- `UPLOADS_ACCESS_KEY_ID`
- `UPLOADS_SECRET_ACCESS_KEY`
- `UPLOADS_ENDPOINT`
- `OTP_PROVIDER_API_KEY`
- `SYNTHETIC_AGENT_ALLOW_REMOTE=1` only in staging jobs that run synthetic traffic

Do not run demo seeds against production after real users exist.

## Release Gate

Before each staging-to-production promotion:

- `npm run lint`
- `npm run test`
- `npm run build`
- `npm run simulate:agents -- --base-url=<staging-url> --agents=12 --ticks=10 --allow-remote=true`

The synthetic-agent run must pass with zero failed HTTP calls. It should be treated as a smoke/load gate, not as a replacement for unit tests or manual product review.

## Rollback Plan

- Keep the previous Railway deployment available for rollback.
- Do not deploy irreversible migrations during launch hours.
- For risky schema changes, prepare a forward-fix migration before deployment.
- Back up production Postgres before each migration release.

## Open Risks

- The current app still writes avatars to local disk.
- The current production start command still applies schema with `db push`.
- OTP still needs real delivery, throttling, and brute-force protection.
- Synthetic agents cover core API flows but do not yet validate full browser rendering or iOS runtime behavior.
