# TennisSearch Iteration 01 Execution Plan

## Objective

Improve the path to the first confirmed game by reducing product friction and stabilizing the most important transitions on Web and iOS.

## Why This Plan

The first team audit shows that the main risk is not missing breadth of features.

The main risk is that:

- users have several overlapping ways to move toward a game
- the “confirmed game” state is not represented as one clear product outcome
- important status changes are easier to miss than they should be
- the core flow is underprotected by tests

Because of that, iteration 01 should stay focused and avoid broad expansion.

## Workstreams

### Workstream 1. Clarify The Core Action Path

Goal:

- make it more obvious what the user should do after discover or match interest

Scope:

- reduce ambiguity between direct proposal and open search
- make next-step calls to action clearer in discover and match contexts
- reduce unnecessary branching for users who just want to get to a game

Primary agents:

- Product Analyst
- Solution Architect
- Frontend Agent
- Mobile Agent

Expected outcome:

- a clearer product path from interest to action on both Web and iOS

### Workstream 2. Make Confirmed Game State Explicit

Goal:

- ensure that once a game is effectively agreed, the user sees one clear and consistent outcome

Scope:

- align how hot search, regular search, game request, regular pair, and chat communicate the next step
- reduce the gap between “approved response”, “scheduled game”, and “confirmed game”
- define the product-canonical place where confirmed-game state is visible

Primary agents:

- Product Analyst
- Solution Architect
- Backend Agent
- Frontend Agent
- Mobile Agent

Expected outcome:

- users understand when a game is actually fixed and where to continue

### Workstream 3. Stabilize Notifications, Status Consistency, And Core-Flow Tests

Goal:

- reduce silent failures and state ambiguity in the path to a real meeting

Scope:

- audit badge and unread behavior for search and game-request events
- improve visibility of key game-status transitions
- add stronger tests for approval, state change, and confirmed-game scenarios

Primary agents:

- Backend Agent
- Matching Agent
- QA Agent

Expected outcome:

- fewer invisible state changes and stronger confidence in the main flow

## Recommended Order

1. freeze product intent for workstream 1 and workstream 2 together
2. align the canonical meaning of “confirmed game”
3. implement Web and iOS UX clarification in parallel after contract decisions
4. implement notification and state-consistency fixes in backend
5. add regression tests before closing the iteration

## Recommended Backlog For Iteration 01

Priority 1:

- define and implement one canonical user-facing “confirmed game” state
- clarify the next best action from discover and from chat

Priority 2:

- reduce overlap and confusion between proposal flow and open search flow
- improve visibility of approval, acceptance, and cancellation events

Priority 3:

- add regression coverage for search approval, game-request transitions, and notification-related state

## Not Recommended This Iteration

- premium work
- large visual redesign
- broad recommendation model expansion
- secondary feature growth that does not improve the path to a real game

## Team Output Expected At The End Of Iteration 01

- a simpler and more understandable path to action
- a clearer confirmed-game experience
- stronger reliability around important state changes
- a short summary of what improved on Web, iOS, backend, and tests
