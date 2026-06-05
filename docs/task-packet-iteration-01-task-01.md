# Task Packet

## Title

Iteration 01 / Task 01 / Clarify The Path To A Confirmed Game

## Request

Reduce friction in the path from discover or search response to a clearly confirmed game on Web and iOS.

## Why This Task Exists

The first product audit showed three linked issues:

- users have overlapping ways to move toward a game
- approval and confirmation states do not resolve into one clear product outcome
- the next step after approval is not always obvious or visible enough

This task is the first implementation task for iteration 01 because it improves the core user journey without expanding scope into secondary systems.

## Product Goal

Make it easier for a user to understand:

1. what action to take next after interest or approval
2. when a game is actually fixed
3. where to continue after the game becomes fixed

## In Scope

- clarify the user-facing path from interest to confirmed game
- define one product-canonical meaning of `confirmed game`
- make the next action clearer after:
  - match creation
  - approved game request
  - approved hot search
  - approved regular search that leads to a regular pair or next-step scheduling
- improve visibility of important state changes in the affected flow
- align Web and iOS on the meaning of the flow, even if implementation details differ

## Out Of Scope

- premium work
- recommendation model redesign
- no-show or reliability system design
- broad onboarding redesign
- large schema redesign unless absolutely required to support the canonical confirmed-game state

## Affected Domains

- user profile readiness
- discover ranking handoff into action
- game request lifecycle
- game search lifecycle
- regular pair handoff
- chat
- notifications
- confirmed meeting state

## Surfaces

- Web
- iOS
- backend

## Product Definition For This Task

For this iteration, `confirmed game` should mean:

- the user can clearly see that a specific play event is fixed enough to act on
- the product gives one obvious place to continue
- the next user action is unambiguous

This does not require solving every future trust or reliability concern.
It does require removing ambiguity from the current flow.

## Acceptance Criteria

### User-Facing

- after a direct game proposal is accepted, the user sees one clear confirmed-game state and one clear next place to continue
- after a hot search is approved and becomes a scheduled game, the user sees the same confirmed-game concept rather than a separate unclear branch
- after a regular search is approved, the user sees a clear next step even if the product does not yet create a directly scheduled game
- the product makes the difference between `response approved`, `game proposed`, and `game confirmed` understandable
- the user is not forced to infer status by reading multiple screens

### Web

- Web surfaces show a clear next action from the relevant points in discover, chat, search lobby, and upcoming/confirmed game areas
- the confirmed-game representation is consistent across the main affected Web surfaces

### iOS

- iOS surfaces show the same product meaning for the same transition points
- navigation after confirmation or approval does not silently fall back without clear user feedback

### Backend / State

- key transitions that lead to confirmed-game state are explicit and consistent
- important status updates that affect the confirmed-game path are visible enough to the user
- no new contradictory state transitions are introduced

### Quality

- regression coverage is expanded for the touched transitions
- risks and non-goals are documented in the final review

## Current Evidence From Audit

Web findings:

- discover and post-match action do not always guide the user toward the best next step
- proposal flow and open search overlap too much
- confirmed game is represented across several disconnected surfaces

iOS findings:

- discover to action is swipe-first and fragmented
- several screens participate in the same flow with different status vocabularies
- confirmed-game related navigation is fragile in places

Backend findings:

- hot search and regular search do not converge into the same kind of product outcome
- notifications and badges are weaker around game-request and approval flows
- tests do not yet protect enough of the core flow

## Recommended Solution Shape

Do not solve this as a broad redesign.

Solve it as a focused alignment task:

1. define canonical states in product language
2. map those states to current backend entities
3. tighten the main next-step actions on Web and iOS
4. improve state visibility in notifications and/or badges where needed
5. protect the transitions with tests

## Technical Constraints

- preserve the current architecture split:
  - `src/server` and `src/lib` for domain logic
  - route handlers in `src/app/**/route.ts`
  - Web UI in `src/components` and `src/app/**/*.tsx`
  - iOS UI in `ios/TennisSearchIOS`
- do not duplicate business logic between client and server
- avoid schema expansion unless a smaller alignment change cannot solve the task
- keep the existing APIs usable for both Web and iOS

## Suggested Module Focus

Potentially affected Web files:

- `src/components/chat/chat-room.tsx`
- `src/components/chat/game-request-card.tsx`
- `src/components/chat/game-search-lobby.tsx`
- `src/components/discover/upcoming-games.tsx`
- `src/components/discover/swipe-deck.tsx`
- `src/components/forms/game-request-form.tsx`
- `src/components/forms/game-search-form.tsx`
- `src/app/play/games/[id]/page.tsx`
- `src/app/play/searches/[id]/page.tsx`

Potentially affected backend files:

- `src/app/game-search-responses/[id]/route.ts`
- `src/app/game-requests/[id]/route.ts`
- `src/app/game-requests/route.ts`
- `src/app/activity/summary/route.ts`
- `src/app/activity/notifications/route.ts`
- `src/server/app-data.ts`
- `src/server/matching.ts`

Potentially affected iOS files:

- `ios/TennisSearchIOS/Views/DiscoverView.swift`
- `ios/TennisSearchIOS/Views/SearchesView.swift`
- `ios/TennisSearchIOS/Views/MatchesView.swift`
- `ios/TennisSearchIOS/Core/AppModels.swift`
- `ios/TennisSearchIOS/Services/NotificationManager.swift`

Potentially affected tests:

- `tests/game-search.test.ts`
- `tests/matching.test.ts`
- new core-flow regression coverage as needed

## Agent Assignment

### Orchestrator / Tech Lead

- split implementation into Web, iOS, backend/state, and QA tracks
- keep the product meaning of `confirmed game` fixed during execution
- ensure no duplicate edits to the same core files without coordination

### Product Analyst

- define the exact product-language distinction between:
  - approved response
  - proposed game
  - confirmed game
- define the preferred next step for each state

### Solution Architect

- map the canonical states to existing entities:
  - `GameRequest`
  - `GameSearch`
  - `GameSearchResponse`
  - `RegularPair`
  - `RegularPairOccurrence`
- decide whether the task can be solved without schema changes

### Backend Agent

- align transitions and visibility for the confirmed-game path
- tighten notification or badge behavior if needed
- add or adjust server-side tests

### Frontend Agent

- clarify Web next-step actions and state representation
- make confirmed-game state easier to understand in the touched surfaces

### Mobile Agent

- align iOS state language and navigation behavior with the canonical product meaning
- reduce silent or fragile navigation around confirmation states

### QA Agent

- validate all key transitions in the path to a confirmed game
- verify that Web and iOS communicate the same product meaning

## Parallelization Rules

Safe in parallel after state definition is frozen:

- Web and iOS UI work
- backend notification/state visibility work and UI wording changes
- QA test-plan preparation

Do not run in parallel:

- changes to canonical state meaning and simultaneous UI implementation before that meaning is fixed
- multiple agents editing the same transition route without ownership split

## Required Checks

- `npm run lint`
- `npm run test`
- `npm run build`

If backend transition logic changes:

- expand or add targeted regression tests for the touched flow

If iOS files change and local environment allows:

- `xcodebuild -project ios/TennisSearchIOS.xcodeproj -scheme TennisSearchIOS -configuration Debug -sdk iphonesimulator build`

## Risks To Watch

- over-scoping into a broad redesign instead of a focused flow clarification
- changing vocabulary without improving actual next-step clarity
- improving Web and leaving iOS semantics behind
- creating a new “confirmed game” concept in UI without backend/state consistency
- introducing more status complexity instead of reducing it

## Definition Of Done For This Task

- the user-facing path to a confirmed game is clearer on Web and iOS
- confirmed-game state has one consistent product meaning in the touched flow
- important transitions are visible enough to the user
- tests protect the touched transitions better than before
- final review lists touched files, checks, risks, and remaining follow-up work
