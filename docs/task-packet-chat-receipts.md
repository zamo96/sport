# Chat delivery and read receipts

## Request and scope

Show whether outgoing chat messages have been delivered and read. Cover existing direct chats, game chats and search lobbies across web, iOS and Android where implemented. Preserve all pre-existing working-tree changes.

## Ownership and sequence

1. Orchestrator: inventory, task packet, integration and required checks.
2. Product Analyst: receipt semantics, acceptance criteria and edge cases.
3. Solution Architect: persistent source of truth, compatible API contract and ownership boundaries.
4. Backend and client specialists implement after contract freeze.
5. Independent QA reviews the stable acceptance checklist, final changes and verification results.

## Domain coverage

- Chat and unread state: affected; message receipts must be independent of global inbox-seen markers.
- Game requests and search lobbies: their chat surfaces are affected; lifecycle transitions remain unchanged.
- Notifications and push devices: regression coverage; push acceptance and presence do not prove message delivery/read.
- Profile, sport/level, geolocation/districts, availability, ranking/recommendations, cancellation/no-show/reliability and premium: unchanged.

## Acceptance checklist

- Outgoing messages show server-confirmed status and distinguish delivery from read.
- Incoming messages and attachment-only messages continue to render normally.
- Read acknowledgements apply only to messages displayed in an active conversation; background fetching and inbox visits do not mark messages read.
- Receipt updates appear without a new message and survive refresh/relaunch.
- Only authorized recipients can acknowledge messages, with no cross-conversation leakage.
- Repeated or out-of-order acknowledgements cannot regress state.
- Old clients/payloads remain compatible; no inferred historical read receipts.
- Group chat wording accurately describes any aggregate receipt state.

## Verification

Completed on 2026-09-08:

| Check | Result |
| --- | --- |
| `npm run prisma:generate` | PASS |
| `npm run lint` | PASS, no warnings |
| `npm run test` (Node 24) | PASS, 79 files / 585 tests |
| `npm run build` (Node 24) | PASS |
| Required iOS Debug simulator build | PASS, arm64 and x86_64 |
| `ios/Tests/run-chat-receipt-tests.sh` | PASS, 29 assertions; independently repeated by QA |
| Android `:app:assembleDebug` | PASS |
| Android `:app:testDebugUnitTest` | PASS, including 4 new receipt tests |
| Real Chromium, two pages, actual game-chat component with mocked transport | PASS, sent/delivered/read, offscreen gating, failed ACK retry, polling refresh and reload |
| Isolated PostgreSQL migration and actual receipt service | PASS; persistence, rerunnable migration, two 24-request concurrency cases, authorization, group counts, constraints and cascade |
| `git diff --check` | PASS |

Final web checks ran again after the blocked-message snapshot fix. Final iOS build ran after the stale-response fix. Default Node 18 cannot start this repository’s installed Vitest/Vite; Node 24 was used successfully. Browser artifacts and logs are under `.artifacts/chat-receipts-*`; iOS build log is `/tmp/tennis-ios-chat-build-verified.log`.

## Frozen API and persistence contract

- `POST /activity/chat-receipts`: exactly one of `matchId`, `gameRequestId`, `searchId`, together with `messageIds` (1–200 actual received incoming IDs) and `status` (`delivered` or `read`). Returns `{ success: true }`. No client timestamps.
- Serialized chat messages optionally expose `receipt: { status: "sent" | "delivered" | "read", deliveredCount: number, readCount: number }`. Older payloads may omit it. Search detail, message lists, newly sent messages and existing shared server-rendered message serializers include summaries when receipt data is loaded.
- A read also confirms delivery. Group status indicates at least one confirmed recipient; user interfaces show counts, with no claim that everyone received/read. Sender is never counted.
- `MessageReceipt` stores one row per message and recipient with server delivery/read timestamps and foreign keys to the user and exactly one of the two message tables. Game-request and match views share receipts for the same physical message. No conversation watermark or historical backfill.
- Transactions recheck conversation authorization, current approved lobby membership, sender exclusion and blocks. Invalid batches fail completely. Unique indexes plus conditional updates preserve first confirmations across duplicate and out-of-order requests. Only a real state advance publishes `chat_receipts_updated` to message senders.
- Existing inbox-seen, push suppression and game lifecycle behavior remain separate. Actual display acknowledgements belong to foreground client message rows; loading inbox/presence alone is never proof of reading.

## Deployment and backend verification

Apply `prisma/deploy/20260908_chat_receipts.sql` before releasing the updated server (or create the Prisma table first and then apply the SQL for its exactly-one-message constraint). It is additive and rerunnable, preserves all chat history, and creates no historical delivery/read facts. Prisma generation alone does not create database tables. Existing clients continue operating but cannot produce confirmations until updated.

Backend targeted validation passed 23 tests (14 receipt tests plus 9 media regressions). The disposable PostgreSQL verification database was dropped and its absence verified; existing database contents were not modified.

## Verification matrix

1. Offline recipient: saved outgoing text/photo remains sent.
2. Fetch acknowledgement advances delivery; visible foreground row advances read.
3. Hidden, background, covered and offscreen messages never create read acknowledgements.
4. Repeat/read-before-delivery/stale responses cannot regress confirmed state.
5. Fetch-to-ack race acknowledges only fetched IDs; batches beyond 200 are split.
6. Stranger, sender, wrong scope, blocked peer and unapproved lobby member acknowledgements are rejected.
7. Group counts exclude the sender and describe observed acknowledgements only.
8. Optional fields preserve legacy model decoding and photo-only rendering.
9. Receipt-only refresh does not force scroll to the latest message.
10. ACK failures remain retryable without preventing send/read UX; successful ACKs do not create realtime loops.


## Changed files and areas

- Backend: `prisma/schema.prisma`, `prisma/deploy/20260908_chat_receipts.sql`, `src/app/activity/chat-receipts/route.ts`, `src/app/game-searches/[id]/route.ts`, `src/server/chat-receipts.ts`, `src/server/chat-media.ts`, `src/server/realtime.ts`, `src/lib/chat-receipts.ts`, `tests/chat-receipts.test.ts`. Shared message includes/serialization bring summaries to all existing message endpoints and SSR without duplicating domain logic.
- Web: `src/components/chat/{chat-room,game-request-chat-room,game-search-lobby,chat-media,chat-receipts}.tsx`, `src/lib/chat-receipts-client.ts`, `tests/chat-receipts-client.test.ts`.
- iOS: `Core/AppModels.swift`, `Services/{APIClient,TennisRepository,MockRepository}.swift`, `Views/{MatchesView,SearchesView,UIComponents}.swift` under `ios/TennisSearchIOS`, plus `ios/Tests/ChatReceiptTests.swift` and its runner.
- Android: `core/Models.kt`, new `core/ChatReceipts.kt`, `data/{TennisRepository,LiveTennisRepository,MockRepository}.kt`, new `ui/components/ChatReceipts.kt`, `ui/matches/ChatScreen.kt`, `ui/searches/SearchLobbyScreen.kt` under `android/app/src/main/java/shop/sportsearch/app`, plus `ChatReceiptsTest.kt` in the corresponding test package.

## Risks and release follow-up

Independent QA verdict: **PASS**. No unresolved findings; iOS stale-response and web blocked-message snapshot findings were corrected and reverified before closure.

- Implementation and local verification are complete; production deployment and database migration were not requested or performed. Apply the documented additive SQL before releasing the server, then release updated clients.
- Older clients remain compatible but cannot acknowledge receipt until updated. No historical delivery/read timestamps are fabricated.
- Browser validation used the real component with mocked HTTP transport; real database service behavior was verified separately. Manual two-account interaction on iOS/Android devices remains a release smoke check.
- Polling fallback updates sender status within the existing chat refresh interval when realtime is unavailable.
- Group counts preserve historical confirmations when participation changes; account/message deletion removes associated receipt rows according to existing deletion policy.
- Pre-existing unrelated working-tree changes were preserved. Ranking, premium, unread badge policy and game lifecycle rules were not changed.
