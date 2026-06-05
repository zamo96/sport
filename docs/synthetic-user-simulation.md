# Synthetic User Simulation

## Purpose

The production gate needs users that behave like real players before real users arrive. The repository now has three useful simulation layers:

- `npm run simulate:acctivity` generates a full database state.
- `npm run simulate:live` keeps creating live database activity.
- `npm run simulate:agents` creates synthetic users and drives real HTTP endpoints with authenticated sessions.

The third mode is the release gate. It exercises auth sessions, API serialization, discover, swipes, game searches, responses, matches, and messages through the same route handlers used by Web and iOS clients.

## How To Run Locally

Start the app first:

```bash
npm run dev:local
```

Then run the synthetic agents:

```bash
npm run simulate:agents -- --base-url=http://127.0.0.1:3002 --agents=8 --ticks=5
```

The simulator creates users with emails like `synthetic+agent-001@tennissearch.local`. By default it resets only those synthetic users before the run.

## How To Run Against Railway Staging

Use the staging database URL in the shell running the simulator and point the simulator at the staging app URL:

```bash
SYNTHETIC_AGENT_ALLOW_REMOTE=1 npm run simulate:agents -- --base-url=https://<staging-app>.up.railway.app --agents=12 --ticks=10 --allow-remote=true
```

Remote execution is guarded because the simulator writes users, sessions, swipes, searches, responses, and messages.

## What It Covers

- Creates or refreshes synthetic onboarded users.
- Creates real server-side sessions in the database.
- Calls `GET /me` and `PATCH /me`.
- Calls `GET /users/discover`.
- Calls `POST /swipes`.
- Calls `POST /game-searches`.
- Calls `POST /game-searches/:id/respond` when compatible active searches exist.
- Calls `GET /game-searches/my`.
- Calls `GET /matches`.
- Calls `POST /matches/:id/messages` when a match exists.

## Pass Criteria

- The process exits with code `0`.
- Every reported endpoint has `failed=0`.
- Average latency is acceptable for staging.
- The database has no unexpected partial state outside synthetic users.

## Limits

- This is not a browser visual test.
- This is not an iOS simulator test.
- It does not use external LLM calls; personas are deterministic so failures are reproducible.
- It does not replace manual trust, moderation, payment, or notification checks.

## Next Iterations

- Add browser-level Playwright journeys for onboarding, discover, search creation, and chat.
- Add a small LLM-driven exploratory mode only in staging, after deterministic synthetic agents are stable.
- Add scenario weights for user personas: passive swiper, hot-search creator, regular partner seeker, chat-heavy user.
- Export JSON metrics for CI/Railway jobs.
