# Required onboarding fields

## Scope and acceptance

Prevent onboarding completion and main-app access without an explicitly selected sport and city. Preserve valid saved selections. Blank/whitespace city, absent location, and an empty sports list are incomplete. Validate both UI navigation and completion handlers, guest promotion, email/Apple sign-in, and restored sessions. Additional schedule, districts, photos, and sport levels retain existing rules.

Affected domains: profile, sport selection, city/location. No ranking, availability rules, game/proposal/search lifecycle, chat/unread, notifications/push, reliability/cancellations, or premium changes. No database migration or backfill.

## Ownership and delivery

Product Analyst supplies acceptance criteria; Solution Architect reviews routing and completion contracts before implementation. Separate owners implement web/backend, iOS, and Android parity. Existing uncommitted work must be preserved. Orchestrator runs mandatory checks and independent QA reviews the final diff against this packet.

Server profile validation remains the persistence source of truth: at least one supported sport and a resolvable city/location are required. Native clients separately distinguish authentication from completed onboarding. Step-one validation must not require a city selected on step two.

## Confirmed causes and design

- iOS `ContentView` and Android `RootScreen` admit any authenticated account even while its onboarding flag is false.
- Mobile sign-in promotes guest drafts using step-one basics, which exclude city. Completion methods also need their own guard rather than relying on a view button.
- Web guest drafts use a default city; account onboarding normalizes absent sports to tennis. These defaults remove the requirement to make an explicit choice.
- Keep the server contract unchanged and cover its existing rejection paths with regression tests. No new endpoint or migration is needed.
- Introduce final completeness checks separately from step-one checks. Restore incomplete drafts and route users to the relevant onboarding step after sign-in/session restore. Preserve completed valid accounts and global catalog locations.
- Make city selection explicit on the web. Do not change the shared sport-normalization fallback used by unrelated product flows.

## Verification checklist

- Reject missing/empty sport and missing/blank city or invalid place without saving completion.
- Valid city plus sport completes without optional fields.
- No silent sport/city defaults in new onboarding forms.
- Email/Apple login and session restore keep incomplete users in onboarding.
- Incomplete guest drafts cannot unlock the main UI or be promoted as complete.
- Existing completed accounts continue normally; saved choices and map visibility are preserved.
- Run lint, full tests, web build, simulator build for iOS changes, and available Android checks for Android changes.

## Results

Implemented on web, iOS, and Android. Independent QA found and verified fixes for incomplete web drafts being cleared after sign-in and an Android global-place payload with blank city. No deployment requested or performed.

### Touched files

- Web: `src/lib/guest-draft.ts`; `src/components/forms/auth-flow.tsx`, `profile-form.tsx`, `guest-profile-page.tsx`, `guest-game-search-page.tsx`; `src/components/discover/guest-discover-screen.tsx`; `src/components/layout/bottom-nav.tsx`; `src/lib/i18n/web/auth.ts`, `profile.ts`.
- Web/backend regression coverage: `tests/required-onboarding.test.ts`, `tests/me-required-onboarding.test.ts`. Backend implementation and API contracts are unchanged.
- iOS: `ios/TennisSearchIOS/Core/AppModels.swift`, `App/AppModel.swift`, `Views/AuthView.swift`, `Views/ContentView.swift`; `ios/Tests/RequiredOnboardingTests.swift`, `run-required-onboarding-tests.sh`.
- Android: `android/app/src/main/java/shop/sportsearch/app/core/Models.kt`, `core/OnboardingRequirements.kt`, `ui/AppViewModel.kt`, `ui/RootScreen.kt`, `ui/auth/AuthScreen.kt`; `android/app/src/test/java/shop/sportsearch/app/core/OnboardingRequirementsTest.kt`; `android/app/build.gradle.kts` (test dependency only).

### Checks

- `npm run lint`: PASS, no warnings/errors.
- `npm run test`: PASS, 77 files / 561 tests.
- `npm run build`: PASS, including Prisma generation, compilation, and type checks.
- `xcodebuild -project ios/TennisSearchIOS.xcodeproj -scheme TennisSearchIOS -configuration Debug -sdk iphonesimulator build`: PASS on final iOS sources.
- `sh ios/Tests/run-required-onboarding-tests.sh`: PASS, 36 assertions executing production model and completion/restore logic with isolated dependencies.
- Android `testDebugUnitTest`: PASS, 8 tests; `assembleDebug`: PASS.
- Android `lintDebug`: FAIL on the preexisting `HighAppVersionCode` (`2026090602`, build.gradle.kts:34), with 54 existing warnings. Release numbering was not changed as part of this fix.

Initial full web checks exposed the shell's outdated Node 18 and a missing optional Sharp runtime. Checks passed with the existing Node 24 runtime after restoring local dependencies; package.json and package-lock.json were not changed. Full tests ran after Prisma generation to avoid concurrently replacing the generated client during test collection.

### Residual risks and follow-up

- Medium verification limitation: no interactive device/email/Apple login walkthrough was performed; native builds, executable regression checks, and independent source review passed. Android had no connected device/emulator.
- Existing Android release configuration lint error must be resolved in release preparation.
- Previously stored web city defaults cannot be distinguished from an explicit selection; saved choices are preserved. Historical web accounts with an administratively forced completion flag are outside this fix; no data backfill is performed.
- No matching formulas, schema, or API contract changes. Existing unrelated uncommitted work remains intact.
