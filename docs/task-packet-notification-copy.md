# Notification copy — 2026-09-09

- Request: change the incoming-like push body to `Открой вкладку «Хотят с тобой поиграть», чтобы ответить.` and explain the existing notification campaigns.
- Product scope: exact push-copy replacement only. The longer in-app feed and mock descriptions are outside scope.
- Design: the backend literal in `src/app/swipes/route.ts` is the source of truth for this push. No API, database, ranking, or client changes.
- Ownership: orchestrator audits campaigns and runs checks; backend specialist updates copy; independent QA reviews acceptance and results.
- Acceptance: requested literal present; title, recipients, trigger, link, sound and preferences preserved; unrelated working-tree changes preserved.
- Verification: lint, test suite, production build, and independent review. No new test for a literal-only change.
- Risk: changes are local until deployment; production campaign enablement is not established by source inspection.
- Check results: `npm run lint` passed; `npm run test` passed with Node 22 (80 files, 595 tests); `npm run build` passed, including Prisma generation and type checking. Default Node 18 could not start Vitest because of an ESM dependency; no dependency changes were needed.
- Campaign audit: seven implemented campaigns; opt-in environment switch defaults off; local `.env` has no explicit switch. Production activation and device delivery were not checked. Standard frequency thresholds are 1/24h and 3/7d; urgent digest thresholds are 2/24h and 10/7d, using shared delivery counts. Quiet hours are 22:00–09:00 in the user's timezone.
- Independent QA: PASS for the scoped copy change and supplied checks. Existing in-app wording remains outside scope. The registry comment saying the hot digest is not connected is stale: its implementation calls `sendCampaignPush`.
