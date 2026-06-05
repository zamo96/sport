# TennisSearch Weekly Review Template

Use this template for the team update to the Product Owner. Keep it concise and product-focused.

## 1. Goal This Week

One sentence.

## 2. What The Team Observed

Top 3 findings only.

- friction in onboarding / profile / discover / chat / search flow
- stability issues
- recommendation quality issues

## 3. What Was Improved

List only product-relevant changes.

- Web
- iOS
- backend
- matching
- reliability

## 4. Expected Product Impact

Short bullets only.

- faster path to first response
- fewer failures in core flow
- clearer next action for users
- better match quality

## 5. Risks Or Open Issues

Up to 5 bullets.

- what is still fragile
- what was not fully verified
- what needs more observation

## 6. What Needs Product Decision

Only include items that actually require Product Owner input.

- priority tradeoff
- scope choice
- metric choice
- policy choice around premium, matching, trust, or UX direction

## 7. Next Recommended Focus

Top 3 items only.

## Ready-To-Use Example

```md
# Weekly Review

## Goal This Week
Improve the path from discover to confirmed game.

## What The Team Observed
- users have multiple next-step options in discover and the flow is not always obvious
- search creation is stronger than direct proposal flow for converting toward a real game
- notification and unread behavior still creates trust issues when state is stale

## What Was Improved
- Web: clarified discover actions and search flow entry points
- iOS: aligned search management flow with Web
- backend: stabilized game-search response handling
- reliability: added regression checks for search and request flows

## Expected Product Impact
- faster move from browsing to action
- fewer abandoned searches
- better confidence in chat and response state

## Risks Or Open Issues
- no-show and reliability scoring are still not first-class product systems
- notification delivery quality still needs observation

## What Needs Product Decision
- whether the next iteration should prioritize recommendation quality or trust/reliability features

## Next Recommended Focus
- reduce friction between match and game proposal
- improve notification confidence
- define reliability model for cancellations and no-shows
```
