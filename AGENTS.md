# TennisSearch Agent Workflow

## Purpose

This repository contains:

- Web client and backend in the root Next.js application
- Shared product logic in `src/lib` and `src/server`
- Database schema and seeds in `prisma/`
- Native iOS client in `ios/TennisSearchIOS`

Use a multi-agent workflow for product work so each change is decomposed, implemented, verified, and closed with explicit risks.

## Repo Map

- `src/app` — Next.js routes, API handlers, and page entrypoints
- `src/components` — web UI components
- `src/lib` — shared validation, scoring, geo, and feature helpers
- `src/server` — server-side domain logic for discover, matching, app data, regular play flows
- `prisma` — schema, seed data, local simulation/import scripts
- `tests` — Vitest coverage for ranking and domain rules
- `ios/TennisSearchIOS` — SwiftUI client and API integration layer

## Agent Roster

### 1. Orchestrator / Tech Lead Agent

Responsibilities:

- intake the feature request, bug report, or refactor goal
- define scope, dependencies, success criteria, and delivery order
- decide which agents are needed and which may work in parallel
- maintain the final task packet and completion checklist

Inputs:

- user request
- current repository state
- open architectural constraints from this file
- outputs from Product Analyst and Solution Architect

Outputs:

- task brief
- decomposition into agent-owned subtasks
- merge plan
- final summary with changed files, checks, and risks

Boundaries:

- may edit documentation, task plans, and orchestration notes
- must not directly implement product logic if a specialist agent owns that area, except for small glue changes

Interaction rules:

- always starts the flow
- must wait for product scope and technical design before dispatching high-risk implementation work
- must send QA a stable acceptance checklist before final review

### 2. Product Analyst Agent

Responsibilities:

- convert product intent into executable requirements
- identify impacted product entities and user flows
- define edge cases, acceptance criteria, and rollout assumptions
- flag monetization, trust, and abuse implications

Inputs:

- feature request or bug report
- current product behavior from code and existing docs
- domain model for profile, sport, level, location, time slots, game requests, matching, chat, notifications, no-show, reliability, premium

Outputs:

- requirement brief
- acceptance criteria
- edge-case checklist
- explicit out-of-scope list

Boundaries:

- does not edit application code
- may edit product documentation and task specs

Interaction rules:

- hands requirements to Solution Architect and Orchestrator
- must call out affected product surfaces: web, iOS, backend, matching, notifications, premium

### 3. Solution Architect Agent

Responsibilities:

- translate requirements into an implementation plan
- define impacted modules, data contracts, migrations, and invariants
- prevent duplication across web, backend, iOS, and matching logic
- choose where shared logic belongs

Inputs:

- requirement brief from Product Analyst
- current architecture in `src/app`, `src/server`, `src/lib`, `prisma`, `ios/TennisSearchIOS`

Outputs:

- technical design note
- module ownership map
- API/data-contract decisions
- risk list for implementation agents

Boundaries:

- may edit architecture docs
- should avoid large code changes unless the task is architecture-only

Interaction rules:

- must define source of truth before Backend and Frontend/Mobile start
- must route ranking logic to Matching Agent, not duplicate it in UI or API handlers

### 4. Backend Agent

Responsibilities:

- implement server routes, domain services, schema changes, and integrations
- keep business logic in `src/server` or `src/lib`, not inside route handlers
- preserve API consistency for web and iOS clients

Inputs:

- technical design note
- API contract
- existing schema and server modules

Outputs:

- code changes in `src/app/**/route.ts`, `src/server`, `src/lib`, `prisma`
- tests for domain behavior and regressions
- migration or seed notes when schema changes

Boundaries:

- owns backend logic, persistence, notification backends, and API serialization
- must not implement SwiftUI screens
- should not implement ranking formulas without Matching Agent alignment

Interaction rules:

- can work in parallel with Frontend/Mobile after contract freeze
- must notify QA about schema changes, seed changes, and backward compatibility risks

### 5. Frontend / Mobile Agent

Responsibilities:

- implement user-facing changes in web or iOS clients
- keep presentation aligned with approved contracts and product behavior
- preserve platform-specific UX while reusing shared business rules

Inputs:

- technical design note
- API contract
- acceptance criteria

Outputs:

- UI changes in `src/components`, `src/app/**/*.tsx`, or `ios/TennisSearchIOS`
- UI-level tests when available
- manual verification notes for affected flows

Boundaries:

- owns client interaction layers only
- must not duplicate domain decisions already handled in `src/server` or `src/lib`
- if both web and iOS are affected, split work into separate subtasks or explicitly assign one agent per client

Interaction rules:

- can run in parallel with Backend after endpoint and payload shape are stable
- must report any contract mismatch immediately back to Orchestrator and Backend

### 6. Matching / Recommendation Agent

Responsibilities:

- own ranking, candidate scoring, recommendation heuristics, and fairness checks
- evolve logic for sport compatibility, level compatibility, availability overlap, distance, reliability, repeat-play signals, and premium modifiers
- protect explainability of match outcomes

Inputs:

- product rules for matching and discovery
- current logic in `src/lib/scoring.ts`, `src/server/discover.ts`, `src/server/matching.ts`
- metrics or qualitative feedback when available

Outputs:

- scoring or recommendation changes
- targeted tests in `tests/`
- explanation of tradeoffs and regression risks

Boundaries:

- owns ranking and eligibility logic
- must not change unrelated UI or transport code unless needed for integration
- must not introduce premium advantages that violate explicit product policy

Interaction rules:

- works with Backend when recommendation changes affect APIs or persistence
- QA must review the regression matrix for discover, search, and match creation flows

### 7. QA Agent

Responsibilities:

- turn scope into a verification matrix
- validate behavior, regressions, and edge cases
- confirm Definition of Done and list unresolved risks

Inputs:

- requirement brief
- technical design note
- final diff and changed-file list
- output from all mandatory checks

Outputs:

- validation report
- regression checklist
- explicit pass/fail decision
- residual risks

Boundaries:

- should not be the primary implementation owner
- may add or adjust tests if gaps block verification

Interaction rules:

- starts test planning once scope is stable
- performs final review after implementation agents finish
- blocks closure if required checks or risk disclosures are missing

## Domain Coverage Rules

Every non-trivial feature must state whether it affects any of the following:

- user profile
- sport and sport-specific level
- geolocation and preferred districts
- availability and time slots
- game request / proposal lifecycle
- game search / lobby lifecycle
- discover ranking and recommendations
- chat and unread state
- notifications and push devices
- cancellations, no-show handling, reliability signals
- premium capabilities and feature gating

If a domain is affected, the responsible agent must update the task packet and tests for that domain.

## Standard Workflow

1. Orchestrator reads the request and creates a task packet.
2. Product Analyst defines acceptance criteria, entities, edge cases, and scope limits.
3. Solution Architect maps the change to modules, contracts, and sequencing.
4. Orchestrator dispatches implementation subtasks.
5. Backend, Frontend/Mobile, and Matching execute in parallel where contracts are stable.
6. QA validates checks, regressions, and residual risk disclosure.
7. Orchestrator assembles the final output with changed files, checks run, and follow-ups.

## Parallel Execution Rules

Safe to run in parallel:

- Product Analyst and repo exploration
- QA test planning and Solution Architect design review
- Backend and Frontend/Mobile after payloads, routes, and state transitions are frozen
- Backend and Matching when a clear ownership split exists
- Web and iOS client work when they touch separate files and use the same approved contract

Do not run in parallel:

- two agents editing the same route, schema, or core shared helper
- Backend and Matching when both are redefining the same ranking or eligibility rule
- Frontend and Backend before request/response shapes are agreed
- final review before all required checks are complete

## Mandatory Checks Before Task Completion

Always run when relevant:

- `npm run lint`
- `npm run test`
- `npm run build`

Run when schema, Prisma client, or seed behavior changes:

- `npm run prisma:generate`

Run when iOS files change and Xcode tooling is available:

- `xcodebuild -project ios/TennisSearchIOS.xcodeproj -scheme TennisSearchIOS -configuration Debug -sdk iphonesimulator build`

If a check cannot be run, the final report must say why and classify the resulting risk.

## Definition of Done

A task is done only when all of the following are true:

- the code builds for every touched surface
- automated tests for the touched surface pass
- lint and type-sensitive build checks pass
- architectural ownership rules in this file are respected
- changed behavior is described in plain language
- key risks and follow-up items are listed
- the touched files and modules are explicit
- database or contract changes are documented
- user-facing flows are verified for regressions

## Final Output Contract

Every completed task should close with:

- short summary of what changed
- list of touched files or areas
- checks executed and their status
- risks, limitations, and follow-up recommendations

If the task changes matching quality, also include:

- what ranking inputs changed
- expected behavior impact
- known false-positive or false-negative risks
