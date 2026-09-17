# Compact map preference and city-only player visibility

## User intent and contract

The user requested a shorter map-visibility label and moving the long explanation behind an info button. They also reported no players on the local map and clarified that a saved city without chosen districts must still show the player across the city.

- Shared label: **Мой профиль на карте / My profile on the map**.
- Closed row contains the label, switch and separate info action. The explanation and registration-only existing-account note appear only after opening information.
- Info must not toggle the preference or submit a form. Web uses a distinct button, unique disclosure IDs and expanded state; native uses an independent accessible 44-point button and system information presentation.
- **Persisted `preferredDistricts: null` is a legacy empty selection and now means the whole city, exactly like `[]`.** The public helper continues to reject missing/undefined query projections and malformed non-null or nonempty invalid preferences. The candidate query explicitly selects this field, so real database null values are known empty states.
- Selected valid districts still limit membership; legacy primary `district` does not invent a chosen play area. No district coverage uses the shared city center. Disabled visibility still yields no map areas.
- Raw PATCH null remains invalid for an active map preference: it must not erase a previously narrow selection through the legacy parser. A stored null left unchanged by a profile update is allowed and renders city-wide.

This supersedes the persisted-null behavior in the earlier district/default-on task packets. Defaults, auth persistence, ranking, map selection and numerical distances do not change.

## Investigation and ownership

Read-only local database inspection found 57 completed, visible accounts; 56 had null/missing district preferences. Local guest discover returned 9 suitable tennis players with visibility enabled but only one with public map areas. This was a general legacy-empty-state interpretation bug, not a visibility-toggle or native marker defect.

An initial synthetic-only repair was cancelled after the user's clarification. No database writes, seed rerun, seed changes or backfill are part of the final solution.

Product/Architect froze the UI contract and revised city-only contract. Web/Backend specialist owns shared web preference UI, translations, public area helper and regression tests. Mobile specialist owns three native UI files. Root owns baseline preservation, builds, live response verification and this packet. Architect performs independent final QA.

The current source baseline is preserved in `/tmp/tennis-map-info-baseline`. Other concurrent changes are retained. Affected domains: profile setting presentation, registration explanation and discovery map membership for legacy city-only records. Sports, levels, ranking, availability, game/search lifecycle, chat, notifications, reliability and premium are unchanged.

## Acceptance and validation

Verify compact closed presentation, independent info/switch behavior and accessible controls; null/empty preferences across covered cities; city-only fallback; selected districts; unknown/malformed/partial projections; opt-out and unchanged PATCH protection. Confirm the live local response contains map areas without editing its records.

Validation so far:

- Lint: PASS (`/tmp/map-info-lint.log`).
- Full tests: PASS, 521 tests / 75 files (`/tmp/map-info-tests.log`). Targeted map/privacy/profile regression suite: 44/44 PASS.
- Live local API: 9/9 matching players now have map areas (previously 1/9), spanning 18 areas and 145 memberships. A read-only evaluation of all 57 local accounts gives 57 map-eligible records; the same 56 stored null preferences remain unchanged.
- Seed changes and the proposed fixture repair were cancelled. No data repair, seed run or database mutation was performed.
- First web/native build attempts failed with `ENOSPC` (temporary disk exhaustion), not source diagnostics. Root removed only its own older reproducible DerivedData and `.next` artifacts. Sequential retries both passed: web production build (`/tmp/map-info-web-build-retry.log`) and native arm64 Debug simulator build (`/tmp/map-info-ios-build-retry.log`).
- All relevant web snapshot sources and the three native UI task files match the successful builds. Unrelated concurrent Android/native work was preserved. Final whitespace validation passed.
- CUA app/browser inventory succeeded, but local browser navigation and subsequent focus commands timed out. Visual layout and info-button interaction are not claimed verified; code review confirms independent actions and accessible controls.

All mandatory automated checks are complete. No schema or seed behavior changes; no production or TestFlight release is part of this task. The cancelled temporary repair script and plan were removed to prevent accidental future execution.

Independent final QA: PASS. Build logs, source hashes, unchanged seed files, the compact info controls and corrected city-only membership were reviewed; no remaining blocking defects were found. Manual visual/interaction verification remains the documented limitation.
