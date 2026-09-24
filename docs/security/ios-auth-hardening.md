# iOS authentication hardening

The iOS and web clients share the same authentication endpoints. No database migration or successful-login response change is required.

## Apple account ownership

Only an Apple-signed email claim with `email_verified: true` (or the string `"true"`) may create an account or link an existing email account. The unsigned request `email` remains accepted for client compatibility but is never used as proof of ownership. A known Apple subject can log in without an email claim. Accounts already bound to another Apple subject are rejected; conditional linking prevents concurrent logins from overwriting a binding.

## OTP limits and deployment requirement

Production email login requires a reachable shared Redis instance configured through `REDIS_URL`. All app instances must use the same limiter store. A missing/unreachable Redis instance causes request/verify endpoints to return safe HTTP 503 (`AUTH_UNAVAILABLE`); login must not silently become unlimited. Existing sessions and Apple sign-in are unaffected. Verify Redis connectivity before deployment.

Limits use independent fixed 10-minute windows: requesting codes allows 5 per email and 30 per source IP; verification allows 10 per email and 100 per source IP. Counters are incremented atomically in Redis, keys hash email and IP, and exceeding either limit returns localized HTTP 429 (`AUTH_RATE_LIMITED`). The trusted reverse proxy must replace `X-Real-IP` / `X-Forwarded-For` headers; requests without them share an `unknown` IP bucket. Development/test has a bounded in-process fallback, unsuitable for production multi-instance enforcement.

Demo review accounts are also rate-limited. Their explicitly configured static code behavior is unchanged. Deactivated accounts cannot create sessions. Code consumption is an atomic conditional update, so concurrent uses of the same one-time code cannot both succeed.

An attacker who knows an email can exhaust that address's temporary budget; limits trade this temporary availability risk for protection from online guessing. Request throttling does not replace infrastructure-level protection against oversized requests or distributed denial of service.

## Logout and push

`POST /auth/logout` accepts an empty body (existing web contract), `{}`, or `{ "pushDeviceToken": "<APNs hex token>" }`. It returns the existing `{ "ok": true }` response. Explicit bearer credentials take precedence over incidental cookies for authentication and logout. The current session is deleted and, when supplied, only the matching iOS push token owned by that session's user is deactivated in the same transaction. Other devices stay active.

APNs registration and logout serialize on the authenticated session row, preventing a delayed registration using a revoked session from reactivating a device. The iOS client must finish pending logout cleanup before registering a fresh session on the same device, especially on relogin to the same account. Network failure during logout can leave remote revocation incomplete and must be treated separately from local credential clearing.

## Verification limits

Regression tests cover signed Apple claims, account-binding conflicts, OTP consumption, shared throttling and failure behavior, bearer/cookie priority, optional logout payload, push ownership predicates, and delayed registration rejection. Database locking paths are covered through query-contract tests; these are not a replacement for a production-like concurrent integration test with PostgreSQL, Redis, and APNs.
