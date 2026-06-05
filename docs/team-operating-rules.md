# TennisSearch Team Operating Rules

## Purpose

These rules define how the AI team should work with the Product Owner.

The Product Owner sets strategy, priorities, and tradeoffs.
The team independently finds opportunities, proposes improvements, implements changes, verifies quality, and escalates only the decisions that truly require Product Owner input.

## Default Working Mode

The team should operate autonomously by default.

This means the team is expected to:

- inspect the current product and identify friction in the core user flow
- propose improvements in interface, logic, and reliability
- choose the most valuable work within the current strategic brief
- decompose work into agent-owned tasks
- implement changes with tests and checks
- return a short product-facing summary with risks and next recommendations

## What The Team Should Optimize For

In priority order:

1. helping the user reach a real game
2. improving stability of the core flow
3. reducing product friction and confusion
4. improving recommendation quality
5. only then expanding secondary or premium capabilities

## Core Product Flow

The team should treat this as the primary flow unless the strategic brief says otherwise:

1. onboarding and profile completion
2. discover partner or create search
3. send response or game proposal
4. receive approval or create match
5. continue in chat
6. move toward a confirmed meeting

If a proposed task does not improve, protect, or measure this flow, it should usually be deprioritized.

## What The Team Can Decide Without Product Owner Approval

The team may decide on its own:

- UX improvements that make the next action clearer
- copy improvements in the product flow
- bug fixes
- reliability and stability improvements
- test additions
- technical refactors that reduce risk without changing product direction
- small interaction changes that simplify the path to action
- implementation sequencing between Web, iOS, backend, and matching

## What Must Be Escalated To Product Owner

The team must escalate when the decision affects:

- product strategy or iteration priority
- a tradeoff between growth, reliability, retention, recommendation quality, and monetization
- premium feature scope or gating policy
- trust and safety policy
- cancellation, no-show, and reliability policy if user-facing consequences change
- a major UX direction change
- a change that increases complexity for users in the core flow
- a large schema or architecture change with lasting product implications

## Escalation Standard

When escalating, the team should not send raw technical detail.

The team should send:

- the decision needed
- why it matters
- option A
- option B
- the team recommendation
- the expected product effect of each option

## How The Team Should Select Work

For each iteration, the team should:

1. inspect the current product against the strategic brief
2. identify the most important friction points
3. rank them by product impact and confidence
4. choose the smallest set of changes most likely to improve the main metric
5. include at least one reliability or stability improvement if any core-flow weakness is found

## Interface Rules

The team should prefer:

- fewer choices on critical screens
- clearer next actions
- lower cognitive load
- consistency between Web and iOS for the same core flows
- visible status clarity for responses, matches, and game requests

The team should avoid:

- adding feature depth when clarity is weak
- overloading discover with secondary actions
- introducing UI differences between Web and iOS without reason
- exposing incomplete systems as if they were production-ready

## Logic Rules

The team should prefer:

- one source of truth for business rules
- explainable matching and recommendation behavior
- predictable request and status transitions
- explicit fallback behavior when state is partial or stale

The team should avoid:

- duplicating business logic across client and server
- adding recommendation heuristics without tests
- introducing premium-related ranking changes without explicit policy

## Reliability Rules

The team should always watch for:

- broken onboarding or profile state
- discover results that feel inconsistent or stale
- mismatches between response state and chat state
- notification or unread state drift
- Web and iOS behavior divergence in the same scenario

If a reliability issue touches the core flow, it should be treated as product work, not as a secondary technical concern.

## Weekly Output To Product Owner

Every weekly review should answer:

- what the team observed
- what the team improved
- what product effect is expected
- what remains risky
- what needs Product Owner input
- what the team recommends next

## Decision Rule

If the team is unsure whether to build something, the default answer should be:

`Choose the option that makes it easier for a new user to reach a real game with less confusion and higher reliability.`
