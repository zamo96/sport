# TennisSearch

TennisSearch is a mobile-first sports partner app for finding players, joining games, managing recurring searches, chatting with matches, and agreeing on a concrete court and time. The repository contains a Next.js web/PWA product, backend API routes, shared domain logic, Prisma data model, and a native SwiftUI iOS client with an upcoming games widget.

## Tech Stack

- Next.js 14, React, TypeScript
- Tailwind CSS
- PostgreSQL and Prisma
- Email OTP authentication for the MVP
- Apple Sign In support for the iOS client
- Provider-agnostic geo and map abstractions
- Yandex Maps JS API v3 for sports center maps
- Installable PWA with an offline shell
- SwiftUI iOS app and WidgetKit upcoming games widget

## Product Scope

- Email OTP sign-in through `POST /auth/request-link` and `POST /auth/verify`
- Apple authentication through `POST /auth/apple`
- Onboarding and profile editing through `GET /me` and `PATCH /me`
- Player discovery ranked by distance, sport, level, format, surface, district, availability, and reliability signals
- Swipe deck with skip and interest actions
- Automatic match creation on mutual interest
- Matches list, chat, unread state, and game request cards
- Sports centers list and map powered by the internal venue database
- One-off game proposals with accept, decline, cancel, reschedule, and share flows
- Regular game searches with responses, lobby chat, participant confirmation, slot proposals, and recurring pair occurrences
- Preferred districts, location-based onboarding, and search radius selection
- Availability by weekday and time range
- User blocking, notifications, and push device registration
- Avatar uploads through local storage or object storage configuration
- Demo seed data and simulation scripts
- Unit tests for scoring, status transitions, sport rules, validators, and explainability

## Repository Layout

- `src/app` - Next.js pages, API routes, and route entrypoints
- `src/components` - web UI components and product flows
- `src/lib` - shared validation, scoring, geo, uploads, auth, and helper logic
- `src/server` - backend domain services for discovery, matching, app data, lobbies, regular play, and activity state
- `prisma` - Prisma schema, seed data, import scripts, and simulators
- `tests` - Vitest coverage for domain rules
- `ios/TennisSearchIOS` - SwiftUI iOS app
- `ios/TennisSearchUpcomingWidget` - WidgetKit upcoming games extension
- `docs` - product briefs, QA notes, deployment docs, import templates, and operating model notes

## Local Development

1. Copy the environment file:

```bash
cp .env.example .env
```

2. To enable Yandex Maps locally, add these values to `.env`:

```bash
NEXT_PUBLIC_MAP_PROVIDER=yandex
NEXT_PUBLIC_YANDEX_MAPS_API_KEY=your_yandex_key
```

3. Start the full local stack:

```bash
npm run dev:local
```

This command starts PostgreSQL in Docker, generates the Prisma client, applies the schema, seeds the database, and starts the Next.js dev server.

Open [http://localhost:3002](http://localhost:3002).

## Demo Flow

On the auth screen, any email can be used in development. The OTP is shown in the UI and printed in the terminal.

Demo users:

- `anna@tennis.dev`
- `elena@tennis.dev`
- `maria@tennis.dev`
- `daria@tennis.dev`
- `sofia@tennis.dev`
- `nina@tennis.dev`

Recommended smoke test:

1. Sign in as a new user or use `anna@tennis.dev`.
2. Complete the onboarding profile.
3. Open the home/discovery tab and swipe player cards.
4. Open matches and enter a chat.
5. Send a game proposal or create a regular game search.
6. Confirm participants, propose slots, and verify the upcoming game state.

## Scripts

- `npm run dev` - start the Next.js dev server only
- `npm run dev:local` - start the full local MVP stack
- `npm run db:start` - start PostgreSQL only
- `npm run db:setup` - run Prisma generate, db push, and seed
- `npm run prisma:generate` - generate Prisma Client
- `npm run prisma:push` - push the Prisma schema to the database
- `npm run prisma:seed` - seed demo data
- `npm run clubs:import` - import sports centers from the configured file
- `npm run simulate:agents` - run the agent simulator
- `npm run simulate:live` - run live simulation data updates
- `npm run build` - production build
- `npm run lint` - ESLint
- `npm run test` - Vitest

## Sports Center Import

Manual import templates are stored in [docs/import](docs/import):

- [clubs.template.csv](docs/import/clubs.template.csv)
- [sports-reference.csv](docs/import/sports-reference.csv)
- [districts-reference.csv](docs/import/districts-reference.csv)
- [metros-spb.reference.csv](docs/import/metros-spb.reference.csv)

To auto-load clubs during `npm run prisma:seed`, either place an Excel file at [docs/import/clubs.xlsx](docs/import/clubs.xlsx) or set `CLUBS_IMPORT_FILE` in `.env`.

When the file is located at `docs/import/clubs.xlsx`, no extra local or Railway setup is required; the seed script picks it up automatically.

## API Surface

- `POST /auth/request-link`
- `POST /auth/verify`
- `POST /auth/apple`
- `POST /auth/logout`
- `GET /me`
- `PATCH /me`
- `GET /users/discover`
- `GET /users/discover/guest`
- `GET /users/discover/likes`
- `POST /users/:id/block`
- `POST /swipes`
- `GET /matches`
- `GET /matches/:id/messages`
- `POST /matches/:id/messages`
- `GET /courts`
- `GET /courts/:id`
- `POST /game-requests`
- `PATCH /game-requests/:id`
- `GET /game-requests/my`
- `GET /game-requests/:id/messages`
- `POST /game-requests/:id/messages`
- `POST /game-requests/:id/share`
- `POST /game-searches`
- `GET /game-searches/my`
- `PATCH /game-searches/:id`
- `POST /game-searches/:id/respond`
- `GET /game-searches/:id/messages`
- `POST /game-searches/:id/messages`
- `POST /game-searches/:id/slot-proposals`
- `POST /game-searches/:id/slot-proposals/:proposalId/votes`
- `PATCH /game-search-responses/:id`
- `PATCH /regular-pairs/:id`
- `PATCH /regular-pairs/:id/occurrences/:occurrenceId`
- `POST /devices/apns`
- `GET /activity/summary`
- `GET /activity/notifications`
- `POST /activity/notifications-seen`
- `POST /activity/inbox-seen`
- `POST /uploads/avatar`

## Web Architecture

- UI routes live under `/discover`, `/inbox`, `/play/courts`, `/play/proposals/new`, `/play/searches`, `/play/regular`, `/profile`, `/settings`, and related subroutes.
- API routes mirror product entities, while UI paths are separated where route collisions would otherwise occur.
- Matching and ranking logic is isolated in `src/server` and `src/lib/scoring.ts`.
- Sport-specific formats and level semantics live in shared helper modules instead of UI components.
- Geo lookup is abstracted in `src/lib/geo.ts`.
- Map provider logic is abstracted under `src/lib/maps`.
- Auth is intentionally lightweight for the MVP and can be replaced with production email delivery or an external auth provider.

## iOS App

The native app lives in `ios/TennisSearchIOS` and shares the same API contracts as the web app. It includes:

- onboarding and profile flows
- location permission handling and district confirmation
- home/discovery screen with swipe cards and guided hints
- matches, chat, proposal, and participant confirmation flows
- regular searches and upcoming games
- profile editing, availability, and preferred play locations
- WidgetKit upcoming games extension

Build the iOS app with:

```bash
xcodebuild -project ios/TennisSearchIOS.xcodeproj -scheme TennisSearchIOS -configuration Debug -sdk iphonesimulator build
```

## Production Notes

- Production environment examples are in [.env.production.example](.env.production.example).
- Railway deployment notes are in [docs/production-rollout-railway.md](docs/production-rollout-railway.md).
- Yandex Object Storage setup for avatars is documented in [docs/yandex-object-storage-avatars.md](docs/yandex-object-storage-avatars.md).
- Yandex Postbox setup for OTP email is documented in [docs/yandex-postbox-otp.md](docs/yandex-postbox-otp.md).
- Deployment assets include [Dockerfile](Dockerfile), [docker-compose.prod.yml](docker-compose.prod.yml), and [deploy/nginx/tennis-search.conf](deploy/nginx/tennis-search.conf).

## Remaining Production Work

- Harden OTP rate limiting and abuse protection.
- Finalize production push notification delivery and background refresh behavior.
- Add admin tooling for sports center database management.
- Move all uploaded media to object storage in production.
- Integrate booking sync with partner venues.
- Add reporting, moderation, bans, and antifraud workflows.
- Expand analytics, observability, and audit logs.
- Add end-to-end and load testing.
- Add payments and subscription management.
