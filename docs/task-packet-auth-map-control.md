# Remove map visibility control from sign-in

## Scope and design

User request: remove “My profile on the map” from the email/Apple sign-in UI. Remove only the sign-in control on web, iOS, and Android and any now-unused component bindings/helpers. Keep the control in profile onboarding and profile settings. Preserve stored choices, new-profile defaults, API payloads, and required-onboarding checks.

Affected surface: presentation of the profile map setting in authentication. No changes to sports/levels, city/district selection, availability, game/proposal/search lifecycle, ranking, chat, notifications/push, reliability, premium, database, or API contracts.

## Ownership and acceptance

Separate web/iOS/Android owners edit each auth view. Orchestrator supplies this scope/design and runs web and iOS checks; Android owner runs its build and tests. Independent QA reviews the final removal.

- Email and Apple sign-in UI no longer shows the map visibility setting or its auth-only explanatory text.
- Profile onboarding and profile settings still show their existing controls.
- No map preference/default/persistence or sign-in/onboarding behavior changes.
- No unused bindings or helper components remain after removal.
- Run existing web lint/tests/build, iOS simulator build, and Android tests/build. No new tests are needed for this reversible presentation-only change.

## Results

Removed the sign-in-only control from `src/components/forms/auth-flow.tsx`, `ios/TennisSearchIOS/Views/AuthView.swift`, and `android/app/src/main/java/shop/sportsearch/app/ui/auth/AuthScreen.kt`. Unused native sign-in bindings/parameters and the Android helper were removed. Profile/onboarding controls, preference defaults, authentication payloads, and persistence remain unchanged.

Checks: web lint PASS; full web tests PASS (77 files / 561 tests); web build PASS; iOS simulator build PASS using the repository-required command; Android unit tests PASS (8/8) and assembleDebug PASS; `git diff --check` PASS. Independent source review passed for all three clients. No new tests were added for this presentation-only removal.

Limitations: no manual device walkthrough was performed. The earlier Android `HighAppVersionCode` lint finding remains unrelated and unchanged; lint was not repeated because release configuration was untouched. Existing unrelated uncommitted changes were preserved. No deployment was performed.
