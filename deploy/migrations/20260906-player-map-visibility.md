# Player map visibility rollout

This repository currently uses Prisma db push; this is a bounded SQL rollout, not a new Prisma migration baseline.

1. Back up the existing database according to the normal deployment process.
2. Apply `20260906-player-map-visibility.sql` to the existing database before deploying the backend that selects `showOnMap`.
3. Apply `20260906-player-map-default-on.sql`. This explicitly requested follow-up enables visibility for **all existing users once** and changes the database default to true for new accounts. It takes a transaction-scoped advisory lock and records `20260906-player-map-default-on-v1` in `DeploymentMigration` atomically with the update. Reapplying it preserves any later user opt-outs. Retain the marker table/row; the Prisma model keeps it in sync with db push. The original SQL remains a historical false-default initializer and must run before this follow-up.
4. Generate the Prisma client and deploy the application. New email/Apple accounts default to visible, with an optional false choice made during registration. Login to an existing account never resets its saved choice. Do not deploy default-on account creation ahead of the SQL.
5. Deploy clients that consume `mapAreas` and can edit visibility in onboarding and profile settings. Guest drafts start enabled and retain an explicit false; promotion can disable the saved account setting, but cannot re-enable a returning account. Missing fields in old responses mean off/empty; older PATCH payloads that omit `showOnMap` preserve the saved setting. An explicit `false` revokes map visibility on the next fresh response.

The additive column is safe to leave in place when rolling back application code. Revoke a setting through `/me`, rather than deleting districts. Retained client snapshots must be refreshed to observe another user's revocation.

Already distributed iOS 1.1.1 clients derive their old map positions from public city/district data and ignore the new flag and area contract. Preserving their PATCH settings does not make their map enforce opt-in. The new visibility behavior requires an updated client; it cannot retract cached/public city information. A coordinated minimum-version policy is separate work if enforcement across every installed client is required.

Map coordinates use only shared catalogue district centers or a canonical GeoPlace city center. An empty district array or persisted null preference means the whole city. Missing/undefined query projections and malformed non-null preferences fail closed. Older PATCH clients that omit district preferences preserve the stored selection; a nonempty invalid/foreign-only list never broadens to whole-city district membership. On save, an opted-in user in a city with district coverage must correct such a list or clear it explicitly. Raw PATCH null cannot erase a previously narrow selection; this is distinct from an already stored legacy null. Cities without district coverage use one public city area and normalize stale district selections to empty.

Ordinary recommendations and existing numerical distance/explainability outputs are unchanged. Approximate distance inference is outside this change. No exact profile home coordinates or private nested User relations are added to public map responses.
