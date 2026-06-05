# TennisSearch Multi-Agent Operating Model

## 1. Target Architecture

TennisSearch already has the right technical split for a specialized agent model:

- web UI in `src/app` and `src/components`
- backend and domain orchestration in `src/server`
- shared business helpers in `src/lib`
- data model in `prisma/schema.prisma`
- native iOS client in `ios/TennisSearchIOS`

Recommended operating model:

```text
Feature Request / Bug Report
        |
        v
Orchestrator / Tech Lead
        |
        +--> Product Analyst
        |
        +--> Solution Architect
        |
        +--> Backend Agent
        |
        +--> Frontend Agent or Mobile Agent
        |
        +--> Matching / Recommendation Agent
        |
        +--> QA Agent
        |
        v
Integrated Change Set + Tests + Risks + Final Review
```

This structure fits the current repo because the main bounded contexts are already visible in code:

- identity and profile
- player discovery and ranking
- game proposals and game searches
- chat and notifications
- regular play flows
- platform-specific clients

## 2. Agent Role Matrix

| Agent | Owns | Typical inputs | Expected outputs | Must avoid |
| --- | --- | --- | --- | --- |
| Orchestrator / Tech Lead | task framing, sequencing, merge plan | request, repo state, design notes | task packet, assignment map, final summary | large specialist implementation by default |
| Product Analyst | scope, edge cases, acceptance criteria | request, current product behavior | requirement brief, DoD additions, out-of-scope | code changes |
| Solution Architect | technical design, contracts, invariants | requirement brief, repo structure | design note, module map, risk map | duplicating implementation work |
| Backend | API, schema, domain rules, integrations | design note, contracts | server diff, tests, migration notes | UI ownership, duplicated ranking logic |
| Frontend Agent | web UX and UI state | contracts, acceptance criteria | `src/app`/`src/components` diff, verification notes | server-side business rules |
| Mobile Agent | SwiftUI and mobile integration | contracts, acceptance criteria | iOS diff, verification notes | backend ownership |
| Matching / Recommendation | scoring, ranking, recommendation behavior | product rules, scoring modules | ranking diff, tests, regression notes | unrelated client work |
| QA | validation and release confidence | final diff, checks, criteria | regression matrix, pass/fail, residual risks | being the main implementer |

## 3. Task Packet Template

Every feature request should be normalized into one task packet before coding starts.

Suggested packet shape:

```md
# Task Packet

## Request
- What problem is being solved?

## Product scope
- In scope
- Out of scope

## Affected domains
- profile
- sport / level
- location
- time slots
- game requests
- game searches
- matching
- chat
- notifications
- no-show / reliability
- premium

## Surfaces
- web
- backend
- iOS

## Acceptance criteria
- ...

## Technical constraints
- ...

## Required checks
- ...

## Assigned agents
- ...
```

## 4. Recommended Codex Workflow

### Stage A. Intake

Owner: Orchestrator

1. Read the request and inspect impacted areas in the repo.
2. Produce a task packet.
3. Decide whether the task is:
   - bugfix
   - small feature
   - cross-surface feature
   - ranking / matching change
   - release / automation work

### Stage B. Product and Design

Owners: Product Analyst, Solution Architect

1. Product Analyst writes acceptance criteria and edge cases.
2. Solution Architect maps the change to current modules.
3. Orchestrator freezes:
   - API shape
   - ownership split
   - verification plan

This is the main gate that prevents duplicated logic between agents.

### Stage C. Implementation

Owners: Backend, Frontend or Mobile, Matching

Parallelization rules:

- Backend and Frontend can run together after route and payload contracts are fixed.
- Backend and Mobile can run together after route and payload contracts are fixed.
- Matching can run with Backend if ranking logic is clearly isolated.
- Web and iOS work should be split if both clients change in the same task.

Not recommended:

- one agent editing `prisma/schema.prisma` while another edits dependent serializers and server logic without a frozen plan
- one agent changing `src/lib/scoring.ts` while another independently changes discover ranking in route handlers

### Stage D. Verification

Owner: QA

1. Validate acceptance criteria.
2. Run mandatory checks.
3. Review touched domains and regressions:
   - discover feed
   - match creation
   - game request state transitions
   - game search responses
   - chat/unread indicators
   - notifications
   - iOS parity when applicable

### Stage E. Final Review

Owners: QA then Orchestrator

Final review should answer:

- what changed
- why the chosen design fits the existing repo
- which files were touched
- which checks ran
- what risks remain
- what follow-up work is still recommended

## 5. Definition of Done for TennisSearch

Base DoD:

- build succeeds for each touched surface
- tests pass for each touched surface
- lint passes
- no architectural ownership violation was introduced
- changed logic is described
- risks are listed
- touched files are explicit

TennisSearch-specific DoD:

- profile changes preserve onboarding and settings behavior
- sport and level changes preserve compatibility rules
- location changes preserve district/radius logic
- availability changes preserve time-slot overlap logic
- game request changes preserve status transitions
- matching changes preserve discover ordering explainability
- chat changes preserve unread/notification behavior
- cancellation or no-show changes describe reliability impact
- premium changes explicitly describe gating and non-premium fallback behavior

## 6. Product-Specific Design Guidance

### User profile

Source of truth:

- `User` model in Prisma
- serializers and validators in `src/lib`
- profile flows in web and iOS clients

Rules:

- do not fork profile shape between web and iOS
- sport preferences and sport-specific levels should remain shared logic

### Sport, level, and matching

Source of truth:

- `src/lib/scoring.ts`
- `src/server/discover.ts`
- `src/server/matching.ts`

Rules:

- avoid scoring logic in UI
- keep ranking explainable and testable
- add tests for new heuristics or premium modifiers

### Geolocation and time slots

Source of truth:

- geo helpers in `src/lib`
- search filters and availability data in Prisma/user payloads

Rules:

- location changes must preserve district fallback behavior
- time-slot changes must be validated across discover, search, and request flows

### Game requests and searches

Source of truth:

- route handlers in `src/app`
- domain logic in `src/server`
- validators in `src/lib/validators.ts`

Rules:

- status transitions belong in shared domain logic
- serializers must stay backward compatible for both clients

### Chat and notifications

Source of truth:

- inbox routes and `src/server/app-data.ts`
- iOS notification integration in `ios/TennisSearchIOS/Services`

Rules:

- unread state and notification state should be treated as one product flow
- if push behavior changes, document fallback behavior for clients without push enabled

### Cancellations, no-show, reliability, premium

Current repo status:

- cancellations exist
- no-show, reliability scoring, and premium appear to be emerging or future domains rather than fully isolated modules

Recommended rule:

- any change introducing these domains must first define a single source of truth and tests before exposing UI-only behavior

## 7. Phased Rollout

### Phase 1. Bugfix + Small Features

Scope:

- single-surface fixes
- copy changes
- validation fixes
- simple route or UI updates
- test backfills

Agent model:

- Orchestrator
- Product Analyst light mode
- one implementation agent
- QA

Success signal:

- team uses task packets and final risk summaries consistently

### Phase 2. Full Feature Flow

Scope:

- web + backend features
- iOS parity work
- schema-backed product changes
- notifications and chat improvements

Agent model:

- full Orchestrator + Product + Architect + Backend + Frontend/Mobile + QA flow

Success signal:

- stable handoffs and fewer duplicated edits across agents

### Phase 3. Recommendation / Matching Improvements

Scope:

- discover ranking
- search prioritization
- reliability-aware recommendations
- premium-aware ranking constraints

Agent model:

- mandatory Matching Agent
- stronger QA regression matrix

Success signal:

- ranking changes always ship with tests, rationale, and risk notes

### Phase 4. Release Automation

Scope:

- release checklists
- automated validation runs
- changelog generation
- deployment and rollout gates

Recommended additions:

- scripted check bundles for web/backend
- iOS build verification in CI or release scripts
- release note template based on the final output contract

## 8. Next Steps for Implementation

1. Adopt `AGENTS.md` as the repository-level instruction file for Codex.
2. Start Phase 1 with bugfixes and small features only for one sprint.
3. Require every non-trivial task to start from a task packet.
4. Enforce the final output contract: summary, touched files, checks, risks.
5. Use [strategic-brief-template.md](/Users/matvey/Desktop/TennisSearch/docs/strategic-brief-template.md) for Product Owner direction at the start of each iteration.
6. Use [weekly-review-template.md](/Users/matvey/Desktop/TennisSearch/docs/weekly-review-template.md) for team updates back to the Product Owner.
7. Add a lightweight template under `docs/` for task packets if the team wants a persistent artifact.
8. After 1-2 weeks, expand to Phase 2 for cross-surface feature work.
9. Introduce a dedicated regression suite for matching before Phase 3 changes.
