# Live check report: Auth sample vs. the real Auth API (second pass, after the API bug-fix PR)

**Date:** 2026-10-31 (UTC). **API:** `https://auth.simpleapi.dev`, running auth-api-private PR #1 (`b79f54f`, "Client-visible changes").
**App:** this branch (`checkKey()` uses `GET /api/keys/check`; handles 400 malformed JSON, lockout `Retry-After`, rate-limit 429).
**Not deployed yet:** auth-api-private PR #2 (stop echoing the apikey in the 401; regenerated `website/public/docs-api.json`). Every row that depends on it still differs live (K9; the K4/K5/K7/K11 messages).

> **This shows what was tried, not that the API (or the app) is bug free.** One pass, one IP, about 114 checks, a shared throwaway demo key.
> It replaces the first report; the earlier results are summarised in "Earlier bugs".

## How it was run

* `tool/live_check/live_check.py` (Python, standard library only). Key from `SIMPLEAPI_KEY` only; never written to a file.
* One full run: **165 requests in 227 s** (paced at 1 per second, plus waits so it stays under the documented rate limit). **4 users** created (A, B, B2, C), all 4 deleted with `DELETE /api/users/me`; none left. At most 3 alive at once. The 15-minute lockout-expiry run was **not repeated** (measured last time: still locked at 14 min, free at 15 min 20 s); the lockout now answers `Retry-After: 895` right after the 5th failure, consistent with that.
* Emails: 1 verification code requested (E1), 2 forgot-password requests (E6 registered, E7 unknown). Nothing read from an inbox.
* **User count:** `GET /api/users` is admin-only, so the count could not be read. As before, deleted users could no longer log in (401, or 429 while their lockout runs).
* Result column: PASS = matched the Expected column. "Observe" rows (M15b, M19, M22, X7, X8) always pass; read the Actual column.
* **114 checks: 110 PASS, 4 FAIL** (RL2, RL3, K9, M5e). RL2, RL3 and K9 are real API findings (below). **M5e is a harness mistake**: it expected the name "Alice Live" but the preceding M4 had legitimately renamed the user to the unicode string, which is exactly what the response shows. The script is fixed; it was not re-run because that would create 4 more users and exceed the budget of 6.

## Earlier bugs

| Earlier finding | Live now | Evidence |
|---|---|---|
| `a@b` accepted as an email (R6, 201) | **Fixed** | R6 `422 The email format is invalid.`; M13b the same for an email change |
| Empty name accepted on update (M5, 200) | **Fixed** | M5 422; also blank (M5b), null (M5c) and empty password (M5d) 422; M5e shows rejected updates changed nothing (name still the M4 value) |
| Malformed JSON gave 422 "name field is required" (R15) | **Fixed** | R15, K10, K12: 400 `Malformed JSON body.  Send a valid JSON object.`; K11: bad key + bad JSON is still 401; K13: `{}` is still 422 |
| Lockout 429 had no `Retry-After`, said "a few minutes" | **Fixed** | X3: `Retry-After: 895`, "Please try again in 15 minutes."; the lock still blocks the right password (X4), is case-insensitive (X5), is per email (X6), applies to unknown emails (X8), keeps existing tokens (X7) and outlives account deletion (Z.C) |
| No way to check a key without a fake login | **Fixed** | K6 `GET /api/keys/check` 200 `{"valid":true}`; K7/K8 401 for unknown/missing key |
| `X-RateLimit-Remaining` jumped around (7 to 19) | **Still broken** | RL2, see below |
| No 429 at 20/min (about 55/min never throttled) | **Still broken** | RL3, see below |
| 401 for an invalid apikey echoes the key text | **Remains, expected** (PR #2 not deployed) | K4, K5, K7, K11, K9 |
| Website docs page stale | Not checked live; fixed in PR #2 (needs deploying) | |
| Changing the email does not end other sessions; no password strength policy | Unchanged, now documented (M15b, M22) | |

## Rate limit (the main open problem)

The rate limiter from PR #1 does **not** behave as documented on the live server.

* **RL2 FAIL, Remaining does not only go down.** 23 requests to `GET /api/keys/check`, one per second, right after waiting for a window to pass, gave `X-RateLimit-Remaining` = 19, 19, 19, 19, 18, 19, 19, 17, 19, 18, 19, 18, 19, 18, 19, 17, 17, 18, 18, 18, 17, 16, 15. It goes up and down, and it never counted more than 5 requests in a row. Across the whole run it ranged from 5 to 19 (`transcript.json` has all 165 values).
* **`X-RateLimit-Reset` is not one value either.** Within those 23 seconds it took 9 different values (`1793486488` ... `1793486501`), each roughly the time of a request + 60 s. A fixed 60 s window per IP would give one value. Every response seems to start its own window, so the counter looks **per worker or per server, not shared** (the requests are served by several independent counters).
* **RL3 FAIL, no 429 at the documented limit.** 23 requests in 23 s (limit 20 per minute) were all 200. In the whole run (165 requests in 227 s, about 44/min) the rate limiter never answered 429; the only 429s were the legitimate ones: the email-code limit (E2) and the login lockout (X2, X4, X5, X8).
* `X-RateLimit-Limit: 20` is present on every response (RL1) and `X-RateLimit-Reset` is now present, so the new headers are deployed; the shared counting is what is wrong. This matches the two causes PR #1 itself listed: a cache that is not shared between workers or servers (for example `CACHE_DRIVER=array`/per-process, or several app servers with local file caches), or a client IP behind nginx that is not the real one. Suggested check on the server: `CACHE_DRIVER`, the number of PHP-FPM pools/hosts, and what `$request->ip()` returns.
* Not tested: the exact 429 body and `Retry-After` of the rate limit (it could not be provoked, RL4/RL5 never ran), and the "20 per minute" behaviour from several IPs.

## Anything new

1. **`Retry-After` and `X-RateLimit-*` are not readable by a browser app.** A cross-origin GET (checked with `Origin: https://simple-api-dev.github.io`) returns `Access-Control-Allow-Origin: *` but no `Access-Control-Expose-Headers`. The Flutter web demo therefore cannot see them (`ApiException.retryAfter` is null on the web build and the app falls back to the fixed "15 minutes" wording). Suggested fix on the API: `Access-Control-Expose-Headers: Retry-After, X-RateLimit-Limit, X-RateLimit-Remaining, X-RateLimit-Reset`. The preflight (OPTIONS) response has no rate-limit headers at all (C1, C2: they show `-`).
2. **Two wordings for a bad email:** `The email format is invalid.` (R6, M13b, the new dotted-domain rule) versus `The email must be a valid email address.` (R5, M13). Harmless, both 422.
3. Messages of the first report still hold: not-found body `{"message":"Not a valid api route - not found."}`; 409 `That email is already registered.`; wrong login 401 `Invalid email or password.` for known and unknown emails (no enumeration).
4. Registered users were created with ids 10 to 13 (the earlier run used 3 to 8), so nobody else seems to have registered on this key in between (inference only).
5. Preflight CORS is unchanged and fine for the demo: allow-origin `*`, methods `POST, GET, OPTIONS, PUT, DELETE`, headers `content-type, authorization, x-requested-with, origin`.

## App bugs

None found against the real responses. `flutter analyze` is clean and `flutter test` passes (83 tests, including the replayed shapes for keys/check, 400, lockout with `Retry-After`, rate-limit 429, `a@b` and empty-name 422). The app handles the missing `Retry-After` (item 1) by design.
One caveat on `ApiException.isBadKey`: it still depends on the word "apikey" in the 401 message, except for `/keys/check`, where any 401 means a bad key. PR #2 keeps the word ("Invalid apikey.").

## Not tested and why

Same as the first report: the emailed-code steps (`/email/verify`, `/users/reset` success), 409 on send-code for a verified email, 403 at 25 users, 403 for a disabled account, the daily email limit 429, token lifetime, a real browser run, the lockout expiry (not repeated), and the user count (admin only). New: the rate-limit 429 body and `Retry-After` (never triggered, see above), and the live website docs page.

## Harness changes in this pass

* Rate-limit aware: waits for the window to end when `X-RateLimit-Remaining` is 1 or less, and retries a `429 Rate limit exceeded` after `Retry-After`; new `--ratelimit-only` mode (RL1 to RL5, no users); checks K6 to K8 use `GET /api/keys/check`; new K9 to K13, M5b to M5e, M13b; R6, R15, M5 and X3 now expect the fixed behaviour.
* The M5e expectation was wrong (see above) and is fixed in the script, not re-run.

## Every check

| ID | Check | Expected | Actual (status + body, trimmed to 140 chars) | Result |
|---|---|---|---|---|
| RL1 | X-RateLimit-Limit and -Reset present on every response | Limit=20, Reset a unix time | `[(200, '20', '19', '1793486488'), (200, '20', '19', '1793486488'), (200, '20', '19', '1793486489')] ...` | PASS |
| RL2 | X-RateLimit-Remaining only goes down within a window | non-increasing, one Reset value | `remaining=[19, 19, 19, 19, 18, 19, 19, 17, 19, 18, 19, 18, 19, 18, 19, 17, 17, 18, 18, 18, 17, 16, 15] resets=['1793486488', '1793486489', '` | FAIL |
| RL3 | a 429 fires at the documented limit (20/min) | first 429 on request 21 of the window | `no 429 in 23 requests` | FAIL |
| K1 | GET /me with no apikey and no token | 401 | `401 {"message":"Unauthorized.  Please provide a valid apikey. Register for a free apikey at https:\/\/keys.simpleapi.dev using product URL h` | PASS |
| K2 | GET /me with valid apikey, garbage token | 401 (must NOT mention apikey) | `401 {"message":"Invalid or expired auth token. Log in again."}` | PASS |
| K3 | login with no apikey | 401 mentioning apikey | `401 {"message":"Unauthorized.  Please provide a valid apikey. Register for a free apikey at https:\/\/keys.simpleapi.dev using product URL h` | PASS |
| K4 | GET /me with unknown apikey (well-formed) | 401 mentioning apikey | `401 {"message":"Unauthorized.  Invalid apikey detected [00000000-0000-0000-0000-000000000000]. Register for a free apikey at https:\/\/keys.` | PASS |
| K5 | GET /me with malformed apikey | 401 mentioning apikey | `401 {"message":"Unauthorized.  Invalid apikey detected [not-a-uuid]. Register for a free apikey at https:\/\/keys.simpleapi.dev using produc` | PASS |
| C1 | CORS preflight for PUT /me from the Pages origin | 2xx, allow-origin, allow Authorization+Content-Type+PUT | `200 "{\"method\":\"OPTIONS\"}"` | PASS |
| C2 | CORS preflight for DELETE /me | 2xx and DELETE allowed | `200 "{\"method\":\"OPTIONS\"}"` | PASS |
| K6 | checkKey(): GET /keys/check with a GOOD key | 200 {"valid":true} | `200 {"valid":true}` | PASS |
| K7 | checkKey(): GET /keys/check with a BAD key | 401 mentioning apikey | `401 {"message":"Unauthorized.  Invalid apikey detected [00000000-0000-0000-0000-000000000000]. Register for a free apikey at https:\/\/keys.` | PASS |
| K8 | checkKey(): GET /keys/check with NO key | 401 mentioning apikey | `401 {"message":"Unauthorized.  Please provide a valid apikey. Register for a free apikey at https:\/\/keys.simpleapi.dev using product URL h` | PASS |
| K9 | invalid apikey 401 does not echo the key text | 401, key not in message | `401 {"message":"Unauthorized.  Invalid apikey detected [00000000-0000-0000-0000-000000000000]. Register for a free apikey at https:\/\/keys.` | FAIL |
| K10 | malformed JSON with a GOOD key | 400 | `400 {"message":"Malformed JSON body.  Send a valid JSON object."}` | PASS |
| K11 | malformed JSON with a BAD key (key is checked first) | 401 | `401 {"message":"Unauthorized.  Invalid apikey detected [00000000-0000-0000-0000-000000000000]. Register for a free apikey at https:\/\/keys.` | PASS |
| K12 | valid JSON that is not an object | 400 | `400 {"message":"Malformed JSON body.  Send a valid JSON object."}` | PASS |
| K13 | empty JSON object is still validated | 422 | `422 {"message":"The email field is required.  The password field is required."}` | PASS |
| R1 | register valid (8-char password = documented minimum) | 201 + token + user | `201 {"token":"<redacted>","expires_at":"2026-11-30T22:41:06.000000Z","user":{"id":10,"name":"Alice Live","email":"<throwaway>@agentmail.to",` | PASS |
| R2 | register response user fields match the app's User.fromJson | id int, name, email, email_verified false, admin false, enabled true, created_at str | `201 {"token":"<redacted>","expires_at":"2026-11-30T22:41:06.000000Z","user":{"id":10,"name":"Alice Live","email":"<throwaway>@agentmail.to",` | PASS |
| R3 | register duplicate email | 409 | `409 {"message":"That email is already registered."}` | PASS |
| R4 | register same email in different case | 409 (emails are case-insensitive) | `409 {"message":"That email is already registered."}` | PASS |
| R5 | register bad email (no @) | 422 | `422 {"message":"The email must be a valid email address."}` | PASS |
| R6 | register bad email (no domain dot) | 422 | `422 {"message":"The email format is invalid."}` | PASS |
| R7 | register password 7 chars | 422 | `422 {"message":"The password must be at least 8 characters."}` | PASS |
| R8 | register password 73 chars (max is 72) | 422 | `422 {"message":"The password may not be greater than 72 characters."}` | PASS |
| R9 | register missing name | 422 | `422 {"message":"The name field is required."}` | PASS |
| R10 | register empty name | 422 | `422 {"message":"The name field is required."}` | PASS |
| R11 | register name 256 chars (max 255) | 422 | `422 {"message":"The name may not be greater than 255 characters."}` | PASS |
| R12 | register missing password | 422 | `422 {"message":"The password field is required."}` | PASS |
| R13 | register missing email | 422 | `422 {"message":"The email field is required."}` | PASS |
| R14 | register empty body | 422 | `422 {"message":"The name field is required.  The email field is required.  The password field is required."}` | PASS |
| R15 | register malformed JSON body | 400 (was 422 before the API fix) | `400 {"message":"Malformed JSON body.  Send a valid JSON object."}` | PASS |
| R16 | validation error WITHOUT Accept header (the app always sends Accept) | 422 JSON | `422 {"message":"The email must be a valid email address.  The password must be at least 8 characters."}` | PASS |
| L1 | login right password | 200 + token + user (new token) | `200 {"token":"<redacted>","expires_at":"2026-11-30T22:41:21.000000Z","user":{"id":10,"name":"Alice Live","email":"<throwaway>@agentmail.to",` | PASS |
| L2 | login wrong password | 401 | `401 {"message":"Invalid email or password."}` | PASS |
| L3 | login with UPPERCASE email | 200 (case-insensitive) | `200 {"token":"<redacted>","expires_at":"2026-11-30T22:41:23.000000Z","user":{"id":10,"name":"Alice Live","email":"<throwaway>@agentmail.to",` | PASS |
| L4 | login unknown email | 401, same message as wrong password | `401 {"message":"Invalid email or password."}` | PASS |
| L5 | login with malformed email | 422 (or 401) | `422 {"message":"The email must be a valid email address."}` | PASS |
| L6 | login missing password | 422 | `422 {"message":"The password field is required."}` | PASS |
| M1 | GET /me | 200 + user | `200 {"id":10,"name":"Alice Live","email":"<throwaway>@agentmail.to","email_verified":false,"admin":false,"enabled":true,"created_at":"2026-1` | PASS |
| M2 | GET /me without token (valid apikey) | 401 | `401 {"message":"Unauthorized. Log in and send the header \"Authorization: Bearer <token>\"."}` | PASS |
| M3 | PUT /me change name | 200 + new name | `200 {"id":10,"name":"Alice Renamed","email":"<throwaway>@agentmail.to","email_verified":false,"admin":false,"enabled":true,"created_at":"202` | PASS |
| M4 | PUT /me unicode / HTML in name round-trips unchanged | 200 + identical name | `200 {"id":10,"name":"Zo\u00eb \ud83d\ude00 \u00f1 <b>x<\/b> & \"q\"","email":"<throwaway>@agentmail.to","email_verified":false,"admin":false` | PASS |
| M5 | PUT /me empty name | 422 | `422 {"message":"The name field is required."}` | PASS |
| M6 | PUT /me name 256 chars | 422 | `422 {"message":"The name may not be greater than 255 characters."}` | PASS |
| M5b | PUT /me blank (spaces) name | 422 | `422 {"message":"The name field is required."}` | PASS |
| M5c | PUT /me null name | 422 | `422 {"message":"The name field is required."}` | PASS |
| M5d | PUT /me empty password | 422 | `422 {"message":"The password field is required."}` | PASS |
| M5e | ...and nothing was changed by those rejected updates | name still Alice Live | `200 {"id":10,"name":"Zo\u00eb \ud83d\ude00 \u00f1 <b>x<\/b> & \"q\"","email":"<throwaway>@agentmail.to","email_verified":false,"admin":false` | FAIL |
| M7 | PUT /me empty body | 200 unchanged or 422 | `200 {"id":10,"name":"Zo\u00eb \ud83d\ude00 \u00f1 <b>x<\/b> & \"q\"","email":"<throwaway>@agentmail.to","email_verified":false,"admin":false` | PASS |
| M8 | PUT /me change email WITHOUT current_password | 403 or 422 (docs: current password required) | `422 {"message":"The current password field is required when email \/ password is present."}` | PASS |
| M8b | ...and the email was NOT changed | email unchanged | `200 {"id":10,"name":"Alice Live","email":"<throwaway>@agentmail.to","email_verified":false,"admin":false,"enabled":true,"created_at":"2026-1` | PASS |
| M9 | PUT /me change email with WRONG current_password | 403 | `403 {"message":"current_password is wrong."}` | PASS |
| M10 | PUT /me change password with WRONG current_password | 403 | `403 {"message":"current_password is wrong."}` | PASS |
| M11 | PUT /me change password WITHOUT current_password | 403 or 422 | `422 {"message":"The current password field is required when email \/ password is present."}` | PASS |
| M12 | PUT /me new password too short (7) | 422 | `422 {"message":"The password must be at least 8 characters."}` | PASS |
| M13 | PUT /me invalid new email | 422 | `422 {"message":"The email must be a valid email address."}` | PASS |
| M13b | PUT /me new email a@b (no dot in domain) | 422 | `422 {"message":"The email format is invalid."}` | PASS |
| B0 | register user B | 201 | `201 {"token":"<redacted>","expires_at":"2026-11-30T22:41:47.000000Z","user":{"id":11,"name":"Bob Live","email":"<throwaway>@agentmail.to","e` | PASS |
| M14 | PUT /me change email to one already registered | 409 | `409 {"message":"That email is already registered."}` | PASS |
| M14b | PUT /me change email to existing one in other case | 409 | `409 {"message":"That email is already registered."}` | PASS |
| M15 | PUT /me change email with right current_password | 200, new email, email_verified false | `200 {"id":10,"name":"Alice Live","email":"<throwaway>@agentmail.to","email_verified":false,"admin":false,"enabled":true,"created_at":"2026-1` | PASS |
| M15b | ...other sessions after an EMAIL change | documented only for password; observe | `200 {"id":10,"name":"Alice Live","email":"<throwaway>@agentmail.to","email_verified":false,"admin":false,"enabled":true,"created_at":"2026-1` | PASS |
| M16 | login with the new email | 200 | `200 {"token":"<redacted>","expires_at":"2026-11-30T22:41:52.000000Z","user":{"id":10,"name":"Alice Live","email":"<throwaway>@agentmail.to",` | PASS |
| M17 | PUT /me change password to 72 chars (max) with right current_password | 200 | `200 {"id":10,"name":"Alice Live","email":"<throwaway>@agentmail.to","email_verified":false,"admin":false,"enabled":true,"created_at":"2026-1` | PASS |
| M18 | other session after password change | 401 (documented: logs out other sessions) | `401 {"message":"Invalid or expired auth token. Log in again."}` | PASS |
| M19 | changing session after password change | 200 (stays logged in) - docs say only OTHER sessions | `200 {"id":10,"name":"Alice Live","email":"<throwaway>@agentmail.to","email_verified":false,"admin":false,"enabled":true,"created_at":"2026-1` | PASS |
| M20 | login with the OLD password | 401 | `401 {"message":"Invalid email or password."}` | PASS |
| M21 | login with the new 72-char password | 200 | `200 {"token":"<redacted>","expires_at":"2026-11-30T22:41:58.000000Z","user":{"id":10,"name":"Alice Live","email":"<throwaway>@agentmail.to",` | PASS |
| M22 | PUT /me weak password '12345678' | documented only min length 8; observe | `200 {"id":10,"name":"Alice Live","email":"<throwaway>@agentmail.to","email_verified":false,"admin":false,"enabled":true,"created_at":"2026-1` | PASS |
| M23 | GET /api/users as a normal user (admin only) | 403 | `403 {"message":"Only the developer account (with a verified email) can list users."}` | PASS |
| E1 | email send-code (request half) | 200 | `200 {"message":"A verification code has been sent to <throwaway>@agentmail.to."}` | PASS |
| E2 | email send-code again immediately | 429 (one per minute) | `429 {"message":"A code was sent a moment ago.  Please wait a minute before asking for another."}` | PASS |
| E3 | send-code without token | 401 | `401 {"message":"Unauthorized. Log in and send the header \"Authorization: Bearer <token>\"."}` | PASS |
| E4 | verify with a wrong code (400 path only) | 400 | `400 {"message":"Invalid or expired verification code."}` | PASS |
| E5 | verify with missing code | 422 | `422 {"message":"The code field is required."}` | PASS |
| E6 | forgot-password for a registered email (request half) | 200 | `200 {"message":"If an account exists for that email, a reset code has been sent."}` | PASS |
| E7 | forgot-password for an UNKNOWN email | 200, identical to E6 (no enumeration) | `200 {"message":"If an account exists for that email, a reset code has been sent."}` | PASS |
| E8 | forgot-password with invalid email | 422 | `422 {"message":"The email must be a valid email address."}` | PASS |
| E9 | reset with a wrong code (400 path only) | 400 | `400 {"message":"Invalid or expired reset code."}` | PASS |
| E10 | reset with missing fields | 422 | `422 {"message":"The code field is required.  The password field is required."}` | PASS |
| O0 | three concurrent sessions for B | 3 different tokens, all valid | `200 {"token":"<redacted>","expires_at":"2026-11-30T22:42:13.000000Z","user":{"id":11,"name":"Bob Live","email":"<throwaway>@agentmail.to","e` | PASS |
| O1 | logout this session (no body, as the app sends) | 200 + message | `200 {"message":"Logged out."}` | PASS |
| O2 | token reuse after logout (GET /me) | 401 | `401 {"message":"Invalid or expired auth token. Log in again."}` | PASS |
| O2b | logout again with the dead token | 401 | `401 {"message":"Invalid or expired auth token. Log in again."}` | PASS |
| O2c | token reuse after logout (PUT /me) | 401 | `401 {"message":"Invalid or expired auth token. Log in again."}` | PASS |
| O3 | other session survives a single logout | 200 | `200 {"id":11,"name":"Bob Live","email":"<throwaway>@agentmail.to","email_verified":false,"admin":false,"enabled":true,"created_at":"2026-10-` | PASS |
| O4 | logout {"all": true} | 200 | `200 {"message":"Logged out of all sessions."}` | PASS |
| O5.2 | session 2 after logout-all | 401 | `401 {"message":"Invalid or expired auth token. Log in again."}` | PASS |
| O5.3 | session 3 after logout-all | 401 | `401 {"message":"Invalid or expired auth token. Log in again."}` | PASS |
| O6 | logout without token | 401 | `401 {"message":"Unauthorized. Log in and send the header \"Authorization: Bearer <token>\"."}` | PASS |
| O7 | can log in again after logout-all | 200 | `200 {"token":"<redacted>","expires_at":"2026-11-30T22:42:23.000000Z","user":{"id":11,"name":"Bob Live","email":"<throwaway>@agentmail.to","e` | PASS |
| X0 | register throwaway user C | 201 | `201 {"token":"<redacted>","expires_at":"2026-11-30T22:42:24.000000Z","user":{"id":12,"name":"Lockout Live","email":"<throwaway>@agentmail.to` | PASS |
| X1 | 4 wrong, right, 4 wrong, right: success resets the failure counter | [401x4,200,401x4,200] if reset (docs silent) | `statuses=[401, 401, 401, 401, 200, 401, 401, 401, 401, 200]` | PASS |
| X2 | 7 consecutive wrong passwords: lockout after 5 | 401x5 then 429 | `statuses=[401, 401, 401, 401, 401, 429, 429]` | PASS |
| X3 | lockout response body / headers | 429, Retry-After 1..900, message says 15 minutes | `429 {"message":"Too many failed logins for this email.  Please try again in 15 minutes."}` | PASS |
| X4 | RIGHT password while locked | 429 (still locked) | `429 {"message":"Too many failed logins for this email.  Please try again in 15 minutes."}` | PASS |
| X5 | RIGHT password, UPPERCASE email, while locked | 429 (lock is case-insensitive) | `429 {"message":"Too many failed logins for this email.  Please try again in 15 minutes."}` | PASS |
| X6 | other user can still log in while C is locked | 200 | `200 {"token":"<redacted>","expires_at":"2026-11-30T22:42:44.000000Z","user":{"id":10,"name":"Alice Live","email":"<throwaway>@agentmail.to",` | PASS |
| X7 | existing token of the locked user | observe (docs silent) | `200 {"id":12,"name":"Lockout Live","email":"<throwaway>@agentmail.to","email_verified":false,"admin":false,"enabled":true,"created_at":"2026` | PASS |
| X8 | 7 wrong passwords for an UNKNOWN email | if 401 throughout, no existence leak; if 429 from the 6th, same as real | `statuses=[401, 401, 401, 401, 401, 429, 429]` | PASS |
| D1 | DELETE /me wrong password | 403 | `403 {"message":"Wrong password."}` | PASS |
| D2 | DELETE /me missing password | 422 (or 403) | `422 {"message":"The password field is required."}` | PASS |
| D3 | DELETE /me without token | 401 | `401 {"message":"Unauthorized. Log in and send the header \"Authorization: Bearer <token>\"."}` | PASS |
| D4 | B still exists after failed deletes | 200 | `200 {"id":11,"name":"Bob Live","email":"<throwaway>@agentmail.to","email_verified":false,"admin":false,"enabled":true,"created_at":"2026-10-` | PASS |
| D5 | DELETE /me right password (user B) | 200 + message | `200 {"message":"Account deleted."}` | PASS |
| D6 | token of deleted user | 401 | `401 {"message":"Invalid or expired auth token. Log in again."}` | PASS |
| D7 | login of deleted user | 401 | `401 {"message":"Invalid email or password."}` | PASS |
| D8 | email is free again after deletion (re-register same address) | 201 | `201 {"token":"<redacted>","expires_at":"2026-11-30T22:43:01.000000Z","user":{"id":13,"name":"Bob Again","email":"<throwaway>@agentmail.to","` | PASS |
| Z.A | after cleanup, login as deleted user A | 401 (429 if a lockout is still running) | `401 {"message":"Invalid email or password."}` | PASS |
| Z.B | after cleanup, login as deleted user B | 401 (429 if a lockout is still running) | `401 {"message":"Invalid email or password."}` | PASS |
| Z.C | after cleanup, login as deleted user C | 401 (429 if a lockout is still running) | `429 {"message":"Too many failed logins for this email.  Please try again in 15 minutes."}` | PASS |
| Z.B2 | after cleanup, login as deleted user B2 | 401 (429 if a lockout is still running) | `401 {"message":"Invalid email or password."}` | PASS |
