# TennisSearch Weekly Review

## Goal This Week

Strengthen the core path from user onboarding and discover to a confirmed game on Web and iOS.

## What The Team Observed

- onboarding and profile completion are fragmented across multiple entry points on both Web and iOS, which weakens data quality for matching and makes readiness unclear
- the product currently offers several overlapping action paths, especially between direct game proposal and open game search, which increases user choice but reduces clarity
- the state of a confirmed game is spread across several screens, cards, and status families, so users may not always feel certain that the meeting is actually fixed
- notification, badge, and unread logic are weaker around game-request and search-confirmation flows than around regular chat messaging
- core-flow test coverage is still shallow relative to the importance of matching, response approval, notification, and confirmed-game transitions

## What Was Improved

- Web: completed a focused product audit of onboarding, discover, proposal, search, chat, and confirmed-game surfaces
- iOS: completed a focused product audit of onboarding, discover, searches, matches, chat, and notification behavior
- backend: completed a focused audit of matching, game-search, game-request, and notification transition logic
- matching: identified the main quality gap between preference-based ranking and real-world reliability or activity signals
- reliability: identified the highest-risk areas for stale state, silent transitions, and low test coverage in the core flow

## Expected Product Impact

- clearer prioritization of the smallest set of changes most likely to improve the path to a real game
- lower risk of spending the first iteration on secondary features instead of core-flow friction
- better alignment between Web, iOS, backend, and matching work before implementation starts

## Risks Or Open Issues

- regular and hot search flows do not lead to the same kind of “confirmed game” outcome today
- users may miss important state changes because game-request events are not as visible as normal chat messages
- the product still lacks a strong trust and reliability layer for ranking and post-match confidence
- state and navigation on iOS appear more fragile where several status systems and fallbacks meet
- automated tests do not yet protect the entire path from search response to confirmed meeting

## What Needs Product Decision

- no immediate product decision is required to begin iteration 1
- the first iteration should remain focused on core-flow clarity and reliability, not on premium or broad feature expansion

## Next Recommended Focus

- simplify and clarify the core action model from discover to game creation
- make confirmed-game state visible and consistent across Web and iOS
- strengthen notification, unread, and regression coverage around search approval and game-request flows
