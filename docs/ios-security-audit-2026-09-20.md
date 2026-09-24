# iOS bug and security audit — 2026-09-20

## Task and acceptance

Audit the native client and its supporting authentication APIs, repair confirmed defects, and run regression checks. This is a source audit and local verification, not an external penetration test of the production service.

1. Logout removes local authentication immediately, survives relaunch, and cannot be undone by old asynchronous responses.
2. Persist credentials in shared Keychain with safe migration from preferences; maintain widget access.
3. Clear account notifications, badges, reminders, widget data, and Live Activities on logout.
4. Late operations from account A cannot overwrite a new account B session or state.
5. Release builds enforce TLS trust and never display response-body excerpts.
6. Apple authentication trusts signed identity claims, OTP consumption is atomic, attempts are limited, and logout revokes the explicit bearer session and its device registration.
7. Preserve existing authentication, onboarding/profile, discover, chat, game and widget contracts.

## Architecture and ownership

The orchestrator acts as solution architect. Product audit supplied the acceptance checklist before implementation.

- Mobile networking specialist: APIClient, secure credential storage shared with the widget, widget networking, entitlements/project references, network regression tests.
- Mobile lifecycle specialist: AppModel, notification lifecycle, local widget/Live Activity clearing, repository protocol/mock, lifecycle regressions.
- Backend specialist: Apple identity binding, OTP consumption/throttling, session lookup/logout, backend regressions.
- Independent QA: final review after implementation and mandatory checks.

The server is the source of truth for account identity. Explicit bearer authentication takes precedence over incidental cookies. `POST /auth/logout` retains web compatibility and accepts optional JSON `{ "pushDeviceToken": "..." }`; it revokes only the captured session and that account's corresponding device registration. The iOS repository gains synchronous `logout(pushDeviceToken:)`: capture the old authenticated request, clear local state immediately, then attempt server cleanup without reading a later account's token. Offline revocation remains best effort.

No schema migration or ranking change is planned. Keychain configuration must preserve app/extension sharing. Client session generations and cancellation checks reject stale responses; tokens are never reintroduced into preferences as a fallback.

## Domain coverage

| Domain | Impact |
| --- | --- |
| User profile | Authentication, privacy, stale profile response isolation |
| Sport and levels | Reviewed; domain rules unchanged |
| Geolocation/districts | Reviewed for privacy; domain rules unchanged |
| Availability/time slots | Reviewed; domain rules unchanged |
| Game proposals | Reminder/widget state isolation |
| Search/lobbies | Existing behavior retained; session isolation |
| Discover/ranking | No ranking or eligibility changes |
| Chat/unread | Notification and account state isolation |
| Notifications/push | Logout cleanup, stale task suppression, device unbinding |
| Cancellation/no-show/reliability | No domain rule changes |
| Premium | No gating or monetization changes |

## Verification plan

Run backend lint, full Vitest suite, production build, all existing iOS regression scripts plus new targeted tests, and Debug simulator Xcode build. Review Release trust configuration. Exercise signed-claim rejection, concurrent OTP consumption, bearer/cookie precedence, device ownership, logout/relogin and delayed response isolation. Record checks, limitations, and follow-ups below when complete.

## Confirmed findings and repair targets

| Priority | Finding | Repair target |
| --- | --- | --- |
| High | Apple sign-in could use an unsigned client email when the identity token omitted it; conflicting linked subjects were not rejected | Signed subject and verified email claims only; conditional account binding |
| High | Logout removed a bearer token but retained an authenticating cookie; backend logout ignored bearer sessions | Cookie-free native sessions, explicit bearer precedence and revocation |
| High | Delayed authentication/profile/notification work could restore previous-account state | Session and monitor generations, cancellation checks |
| Medium | App and widget stored bearer credentials in ordinary preferences | Shared Keychain and removal of legacy preference copies |
| Medium | Logout left private widget, reminder, badge and media state | Direct cleanup independent of which view is visible |
| Medium | OTP consumption was a read followed by unconditional write; attempts were not limited | Atomic conditional consumption and shared request/verification limits |
| Medium | Device registration survived logout | Account-scoped device deactivation during session revocation |
| Medium | Error construction included raw server response excerpts | User-safe errors without response contents |
| Hardening | Certificate bypass depended only on configuration | Compile-time exclusion from Release |

Apple's documentation informs the identity and storage design: [Sign in with Apple identity claims](https://developer.apple.com/documentation/signinwithapple/authenticating-users-with-sign-in-with-apple) and [Keychain data protection](https://support.apple.com/en-tm/guide/security/secb0694df1a/web).

## Deployment and verification limits

- Production OTP requires reachable shared Redis (`REDIS_URL`); failure returns HTTP 503 instead of allowing unlimited guesses. The production Compose configuration already supplies Redis. See [authentication deployment notes](security/ios-auth-hardening.md).
- Shared Keychain requires matching app/extension signing and provisioning entitlements; a simulator build does not validate distribution provisioning.
- Logout clears local access immediately. If the network is unavailable, remote session revocation is best effort; a previously copied server token can remain valid until expiry/revocation.
- Some non-chat upload handlers parse multipart bodies before validating individual file sizes. The checked-in Nginx configuration caps upload request bodies at 85 MiB. Preserve that cap and prevent public access that bypasses the proxy; app-layer streaming limits remain a further hardening opportunity.
- Physical-device Apple login, APNs delivery, WidgetKit refresh timing, and live PostgreSQL/Redis concurrency require staging/device validation. Local tests do not establish that every vulnerability has been eliminated.

## Additional repaired lifecycle cases

Profile photo/video preparation and queued profile writes now capture the initiating session before asynchronous work. Switching accounts cannot apply a previous profile operation to a new credential. Explicit logout also clears the incomplete onboarding draft and media caches.

Startup waits for session restoration before exposing interactive guest/authenticated screens. A temporary restore failure offers Retry or explicit Continue as guest; it does not silently show guest actions while a stored authenticated credential remains active. Unauthorized restoration clears local state. A successful login followed by a failed profile fetch revokes the newly acquired session. If optional onboarding draft promotion fails after the user is adopted, notification monitoring still starts.

## Check results

| Check | Result |
| --- | --- |
| `npm run lint` | PASS, no warnings/errors |
| `npm run test` | PASS, 91 files / 683 tests |
| `npm run build` | PASS, including type checks and Prisma client generation |
| Chat receipts | PASS, 29 assertions |
| Mock inbox seen state | PASS, 21 assertions |
| Player auto-advance | PASS, 485 assertions |
| Player map | PASS, 84 assertions |
| Required onboarding | PASS, 36 checks |
| Widget schedule/store | PASS, 34 + 11 checks |
| API security | PASS, 21 runtime assertions |
| Secure session store | PASS, 9 actual macOS Keychain assertions; iOS access-group/protection behavior not established by this test |
| Notification lifecycle | PASS, 9 adversarial checks |
| Session lifecycle | PASS, 26 checks |
| Media lifecycle | PASS, 6 checks |
| Debug simulator build | PASS, final sources, arm64 + x86_64 |
| Release simulator build | PASS, arm64 |
| Independent QA source review | PASS, no blocking findings |

Full Xcode builds retain pre-existing AVFoundation warnings in video trimming (`AVAsset.duration` deprecation and `AVAssetExportSession` Sendable capture). The new unused-result warning was fixed; the final incremental Debug build is clean. Physical-device signing remains unverified.

The final Debug app installed and launched successfully on a newly created, isolated iPhone 17 Pro simulator (iOS 26.3). The existing local Debug configuration points at a local development server that was unavailable during the smoke check. Visual inspection confirmed the restoration progress screen and the resulting safe failure screen with Retry / Continue as guest; neither clipped content nor a crash was observed. No production account was used. Interactive authenticated flows were covered by the regression harnesses, not by a live signed-in simulator session. The temporary simulator was removed afterward.

Independent QA's final verdict is **PASS for the audited scope**, with no blocking defects in the final diff and the device/staging limitations above. Database schema and ranking rules are unchanged.

During final workspace inspection, concurrent changes appeared in regular-play routes, regular occurrences, and server notification/reminder modules. Those changes were preserved and are outside this audit. The server check results above describe the auth/iOS audit snapshot before those unrelated edits appeared.
