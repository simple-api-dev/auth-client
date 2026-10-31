# Live check report: Auth sample vs. the real Auth API

**Date:** 2026-10-31 (UTC). **API:** `https://auth.simpleapi.dev` (Swagger v2.0, from `/api/docs`).
**App:** `lib/auth_api.dart` on `main` at `ffc738a` (includes `checkKey()` and `isUserCapReached`).

> **This shows what was tried, not that the API (or the app) is bug free.** One pass, one IP, one
> afternoon, about 110 checks, using a shared throwaway demo key. Absence of a finding is not evidence of absence.

## How it was run

* `tool/live_check/live_check.py` (Python, standard library only). Key from `SIMPLEAPI_KEY` only; never written to a file.
  `apikey` is a query parameter, `Authorization: Bearer` on protected calls, exactly as `AuthApi` does.
* Main run: 130 requests in 143 s (about one per 1.1 s), **5 users** created, all 5 deleted with `DELETE /api/users/me`.
  Lockout-expiry run: 11 requests over 15.5 min, **1 user**, deleted. Total **6 users** (the cap I was given), at most 4 alive at once.
  A 7th run was not possible without exceeding that budget, see "Harness caveats".
* **User count:** `GET /api/users` is admin-only (verified: a normal user gets 403), so I could not read the count. Evidence the
  rows are really gone instead: after cleanup, `login` as every deleted user returned 401 `Invalid email or password.`,
  the deleted users' tokens returned 401, and an email freed by deletion could be registered again (D8).
  The ids handed out were 3 to 8, consecutive, which suggests nobody else registered on this key during the runs (an inference, not something the API states).
* **Rate limit:** no `429 Throttle Limit Exceeded` (the sibling Reviews API message) was ever seen in about 150 requests, including
  bursts at the 1.1 s pace (about 55 requests/minute). Every response did carry `X-RateLimit-Limit: 20`, but `X-RateLimit-Remaining`
  jumped around (7 to 19, not counting down), and 20 per minute was clearly not enforced at 55/minute. See API notes.
* **Emails:** the main run requested 1 verification code (E1) and made 2 forgot-password requests (E6 registered address, E7 unknown address); the 2nd send-code was refused with 429 before any email.
  Nothing was read from an inbox.
* Result column: PASS means "matched the expectation in the Expected column". For rows whose expectation is "observe" (M15b, M19, M22, X7, X8)
  the harness records what happened and always passes; read the Actual column and the notes below. Row Z.C below is a harness expectation
  that was too strict (explained there), not an API failure.

## Every check

| ID | Check | Expected (per docs / assumption) | Actual (status + body, trimmed) | Result |
|---|---|---|---|---|
| K1 | GET /me with no apikey and no token | 401 | `401 {"message":"Unauthorized.  Please provide a valid apikey. Register for a free apikey at https:\/\/keys.simpleapi.dev using product URL h` | PASS |
| K2 | GET /me with valid apikey, garbage token | 401 (must NOT mention apikey) | `401 {"message":"Invalid or expired auth token. Log in again."}` | PASS |
| K3 | login with no apikey | 401 mentioning apikey | `401 {"message":"Unauthorized.  Please provide a valid apikey. Register for a free apikey at https:\/\/keys.simpleapi.dev using product URL h` | PASS |
| K4 | GET /me with unknown apikey (well-formed) | 401 mentioning apikey | `401 {"message":"Unauthorized.  Invalid apikey detected [00000000-0000-0000-0000-000000000000]. Register for a free apikey at https:\/\/keys.` | PASS |
| K5 | GET /me with malformed apikey | 401 mentioning apikey | `401 {"message":"Unauthorized.  Invalid apikey detected [not-a-uuid]. Register for a free apikey at https:\/\/keys.simpleapi.dev using produc` | PASS |
| C1 | CORS preflight for PUT /me from the Pages origin | 2xx, allow-origin, allow Authorization+Content-Type+PUT | `200 "{\"method\":\"OPTIONS\"}"` | PASS |
| C2 | CORS preflight for DELETE /me | 2xx and DELETE allowed | `200 "{\"method\":\"OPTIONS\"}"` | PASS |
| R1 | register valid (8-char password = documented minimum) | 201 + token + user | `201 {"token":"…","expires_at":"2026-11-30T20:40:37.000000Z","user":{"id":3,"name":"Alice Live","email":"simpleapi-sample-apps+099e2` | PASS |
| R2 | register response user fields match the app's User.fromJson | id int, name, email, email_verified false, admin false, enabled true, created_at str | `201 {"token":"…","expires_at":"2026-11-30T20:40:37.000000Z","user":{"id":3,"name":"Alice Live","email":"simpleapi-sample-apps+099e2` | PASS |
| R3 | register duplicate email | 409 | `409 {"message":"That email is already registered."}` | PASS |
| R4 | register same email in different case | 409 (emails are case-insensitive) | `409 {"message":"That email is already registered."}` | PASS |
| R5 | register bad email (no @) | 422 | `422 {"message":"The email must be a valid email address."}` | PASS |
| R6 | register bad email (no domain dot) | 422 | `201 {"token":"…","expires_at":"2026-11-30T20:40:41.000000Z","user":{"id":4,"name":"X","email":"a@b","email_verified":false,"admin":` | FAIL |
| R7 | register password 7 chars | 422 | `422 {"message":"The password must be at least 8 characters."}` | PASS |
| R8 | register password 73 chars (max is 72) | 422 | `422 {"message":"The password may not be greater than 72 characters."}` | PASS |
| R9 | register missing name | 422 | `422 {"message":"The name field is required."}` | PASS |
| R10 | register empty name | 422 | `422 {"message":"The name field is required."}` | PASS |
| R11 | register name 256 chars (max 255) | 422 | `422 {"message":"The name may not be greater than 255 characters."}` | PASS |
| R12 | register missing password | 422 | `422 {"message":"The password field is required."}` | PASS |
| R13 | register missing email | 422 | `422 {"message":"The email field is required."}` | PASS |
| R14 | register empty body | 422 | `422 {"message":"The name field is required.  The email field is required.  The password field is required."}` | PASS |
| R15 | register malformed JSON body | 4xx, not 5xx | `422 {"message":"The name field is required.  The email field is required.  The password field is required."}` | PASS |
| R16 | validation error WITHOUT Accept header (the app always sends Accept) | 422 JSON | `422 {"message":"The email must be a valid email address.  The password must be at least 8 characters."}` | PASS |
| L1 | login right password | 200 + token + user (new token) | `200 {"token":"…","expires_at":"2026-11-30T20:40:53.000000Z","user":{"id":3,"name":"Alice Live","email":"simpleapi-sample-apps+099e2` | PASS |
| L2 | login wrong password | 401 | `401 {"message":"Invalid email or password."}` | PASS |
| L3 | login with UPPERCASE email | 200 (case-insensitive) | `200 {"token":"…","expires_at":"2026-11-30T20:40:55.000000Z","user":{"id":3,"name":"Alice Live","email":"simpleapi-sample-apps+099e2` | PASS |
| L4 | login unknown email | 401, same message as wrong password | `401 {"message":"Invalid email or password."}` | PASS |
| L5 | login with malformed email | 422 (or 401) | `422 {"message":"The email must be a valid email address."}` | PASS |
| L6 | login missing password | 422 | `422 {"message":"The password field is required."}` | PASS |
| M1 | GET /me | 200 + user | `200 {"id":3,"name":"Alice Live","email":"<throwaway>@agentmail.to","email_verified":false,"admin":false,"enabled":true,` | PASS |
| M2 | GET /me without token (valid apikey) | 401 | `401 {"message":"Unauthorized. Log in and send the header \"Authorization: Bearer <token>\"."}` | PASS |
| M3 | PUT /me change name | 200 + new name | `200 {"id":3,"name":"Alice Renamed","email":"<throwaway>@agentmail.to","email_verified":false,"admin":false,"enabled":tr` | PASS |
| M4 | PUT /me unicode / HTML in name round-trips unchanged | 200 + identical name | `200 {"id":3,"name":"Zo\u00eb \ud83d\ude00 \u00f1 <b>x<\/b> & \"q\"","email":"<throwaway>@agentmail.to","email_verified"` | PASS |
| M5 | PUT /me empty name | 422 | `200 {"id":3,"name":"","email":"<throwaway>@agentmail.to","email_verified":false,"admin":false,"enabled":true,"created_a` | FAIL |
| M6 | PUT /me name 256 chars | 422 | `422 {"message":"The name may not be greater than 255 characters."}` | PASS |
| M7 | PUT /me empty body | 200 unchanged or 422 | `200 {"id":3,"name":"","email":"<throwaway>@agentmail.to","email_verified":false,"admin":false,"enabled":true,"created_a` | PASS |
| M8 | PUT /me change email WITHOUT current_password | 403 or 422 (docs: current password required) | `422 {"message":"The current password field is required when email \/ password is present."}` | PASS |
| M8b |   ...and the email was NOT changed | email unchanged | `200 {"id":3,"name":"Alice Live","email":"<throwaway>@agentmail.to","email_verified":false,"admin":false,"enabled":true,` | PASS |
| M9 | PUT /me change email with WRONG current_password | 403 | `403 {"message":"current_password is wrong."}` | PASS |
| M10 | PUT /me change password with WRONG current_password | 403 | `403 {"message":"current_password is wrong."}` | PASS |
| M11 | PUT /me change password WITHOUT current_password | 403 or 422 | `422 {"message":"The current password field is required when email \/ password is present."}` | PASS |
| M12 | PUT /me new password too short (7) | 422 | `422 {"message":"The password must be at least 8 characters."}` | PASS |
| M13 | PUT /me invalid new email | 422 | `422 {"message":"The email must be a valid email address."}` | PASS |
| B0 | register user B | 201 | `201 {"token":"…","expires_at":"2026-11-30T20:41:16.000000Z","user":{"id":5,"name":"Bob Live","email":"simpleapi-sample-apps+9f7b1da` | PASS |
| M14 | PUT /me change email to one already registered | 409 | `409 {"message":"That email is already registered."}` | PASS |
| M14b | PUT /me change email to existing one in other case | 409 | `409 {"message":"That email is already registered."}` | PASS |
| M15 | PUT /me change email with right current_password | 200, new email, email_verified false | `200 {"id":3,"name":"Alice Live","email":"<throwaway>@agentmail.to","email_verified":false,"admin":false,"enabled":true,` | PASS |
| M15b |   ...other sessions after an EMAIL change | documented only for password; observe | `200 {"id":3,"name":"Alice Live","email":"<throwaway>@agentmail.to","email_verified":false,"admin":false,"enabled":true,` | PASS |
| M16 | login with the new email | 200 | `200 {"token":"…","expires_at":"2026-11-30T20:41:22.000000Z","user":{"id":3,"name":"Alice Live","email":"simpleapi-sample-apps+6e994` | PASS |
| M17 | PUT /me change password to 72 chars (max) with right current_password | 200 | `200 {"id":3,"name":"Alice Live","email":"<throwaway>@agentmail.to","email_verified":false,"admin":false,"enabled":true,` | PASS |
| M18 | other session after password change | 401 (documented: logs out other sessions) | `401 {"message":"Invalid or expired auth token. Log in again."}` | PASS |
| M19 | changing session after password change | 200 (stays logged in) - docs say only OTHER sessions | `200 {"id":3,"name":"Alice Live","email":"<throwaway>@agentmail.to","email_verified":false,"admin":false,"enabled":true,` | PASS |
| M20 | login with the OLD password | 401 | `401 {"message":"Invalid email or password."}` | PASS |
| M21 | login with the new 72-char password | 200 | `200 {"token":"…","expires_at":"2026-11-30T20:41:29.000000Z","user":{"id":3,"name":"Alice Live","email":"simpleapi-sample-apps+6e994` | PASS |
| M22 | PUT /me weak password '12345678' | documented only min length 8; observe | `200 {"id":3,"name":"Alice Live","email":"<throwaway>@agentmail.to","email_verified":false,"admin":false,"enabled":true,` | PASS |
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
| O0 | three concurrent sessions for B | 3 different tokens, all valid | `200 {"token":"…","expires_at":"2026-11-30T20:41:45.000000Z","user":{"id":5,"name":"Bob Live","email":"simpleapi-sample-apps+9f7b1da` | PASS |
| O1 | logout this session (no body, as the app sends) | 200 + message | `200 {"message":"Logged out."}` | PASS |
| O2 | token reuse after logout (GET /me) | 401 | `401 {"message":"Invalid or expired auth token. Log in again."}` | PASS |
| O2b | logout again with the dead token | 401 | `401 {"message":"Invalid or expired auth token. Log in again."}` | PASS |
| O2c | token reuse after logout (PUT /me) | 401 | `401 {"message":"Invalid or expired auth token. Log in again."}` | PASS |
| O3 | other session survives a single logout | 200 | `200 {"id":5,"name":"Bob Live","email":"<throwaway>@agentmail.to","email_verified":false,"admin":false,"enabled":true,"c` | PASS |
| O4 | logout {"all": true} | 200 | `200 {"message":"Logged out of all sessions."}` | PASS |
| O5.2 | session 2 after logout-all | 401 | `401 {"message":"Invalid or expired auth token. Log in again."}` | PASS |
| O5.3 | session 3 after logout-all | 401 | `401 {"message":"Invalid or expired auth token. Log in again."}` | PASS |
| O6 | logout without token | 401 | `401 {"message":"Unauthorized. Log in and send the header \"Authorization: Bearer <token>\"."}` | PASS |
| O7 | can log in again after logout-all | 200 | `200 {"token":"…","expires_at":"2026-11-30T20:41:56.000000Z","user":{"id":5,"name":"Bob Live","email":"simpleapi-sample-apps+9f7b1da` | PASS |
| X0 | register throwaway user C | 201 | `201 {"token":"…","expires_at":"2026-11-30T20:41:57.000000Z","user":{"id":6,"name":"Lockout Live","email":"simpleapi-sample-apps+951` | PASS |
| X1 | 4 wrong, right, 4 wrong, right: success resets the failure counter | [401x4,200,401x4,200] if reset (docs silent) | `statuses=[401, 401, 401, 401, 200, 401, 401, 401, 401, 200]` | PASS |
| X2 | 7 consecutive wrong passwords: lockout after 5 | 401x5 then 429 | `statuses=[401, 401, 401, 401, 401, 429, 429]` | PASS |
| X3 | lockout response body / headers | 429 with message + Retry-After | `429 {"message":"Too many failed logins for this email.  Please try again in a few minutes."}` | PASS |
| X4 | RIGHT password while locked | 429 (still locked) | `429 {"message":"Too many failed logins for this email.  Please try again in a few minutes."}` | PASS |
| X5 | RIGHT password, UPPERCASE email, while locked | 429 (lock is case-insensitive) | `429 {"message":"Too many failed logins for this email.  Please try again in a few minutes."}` | PASS |
| X6 | other user can still log in while C is locked | 200 | `200 {"token":"…","expires_at":"2026-11-30T20:42:19.000000Z","user":{"id":3,"name":"Alice Live","email":"simpleapi-sample-apps+6e994` | PASS |
| X7 | existing token of the locked user | observe (docs silent) | `200 {"id":6,"name":"Lockout Live","email":"<throwaway>@agentmail.to","email_verified":false,"admin":false,"enabled":tru` | PASS |
| X8 | 7 wrong passwords for an UNKNOWN email | if 401 throughout, no existence leak; if 429 from the 6th, same as real | `statuses=[401, 401, 401, 401, 401, 429, 429]` | PASS |
| D1 | DELETE /me wrong password | 403 | `403 {"message":"Wrong password."}` | PASS |
| D2 | DELETE /me missing password | 422 (or 403) | `422 {"message":"The password field is required."}` | PASS |
| D3 | DELETE /me without token | 401 | `401 {"message":"Unauthorized. Log in and send the header \"Authorization: Bearer <token>\"."}` | PASS |
| D4 | B still exists after failed deletes | 200 | `200 {"id":5,"name":"Bob Live","email":"<throwaway>@agentmail.to","email_verified":false,"admin":false,"enabled":true,"c` | PASS |
| D5 | DELETE /me right password (user B) | 200 + message | `200 {"message":"Account deleted."}` | PASS |
| D6 | token of deleted user | 401 | `401 {"message":"Invalid or expired auth token. Log in again."}` | PASS |
| D7 | login of deleted user | 401 | `401 {"message":"Invalid email or password."}` | PASS |
| D8 | email is free again after deletion (re-register same address) | 201 | `201 {"token":"…","expires_at":"2026-11-30T20:42:37.000000Z","user":{"id":7,"name":"Bob Again","email":"simpleapi-sample-apps+9f7b1d` | PASS |
| Z.A | after cleanup, login as deleted user A | 401 | `401 {"message":"Invalid email or password."}` | PASS |
| Z.stray-R6 | after cleanup, login as deleted user stray-R6 | 401 | `401 {"message":"Invalid email or password."}` | PASS |
| Z.B | after cleanup, login as deleted user B | 401 | `401 {"message":"Invalid email or password."}` | PASS |
| Z.C | after cleanup, login as deleted user C | 401 | `429 {"message":"Too many failed logins for this email.  Please try again in a few minutes."}` | FAIL |
| Z.B2 | after cleanup, login as deleted user B2 | 401 | `401 {"message":"Invalid email or password."}` | PASS |
| K6 | `checkKey()`: POST /login with `{}` and a GOOD key (added after main changed; separate 10-request run) | 422 | `422 {"message":"The email field is required.  The password field is required."}` | PASS |
| K7 | `checkKey()`: same with a well-formed but unknown key | 401 mentioning apikey | `401 {"message":"Unauthorized.  Invalid apikey detected [0000…]. Register for a free apikey at …"}` | PASS |
| K8 | `checkKey()`: same with no key | 401 mentioning apikey | `401 {"message":"Unauthorized.  Please provide a valid apikey. …"}` | PASS |
| W1-W2 | Lockout expiry run (1 more throwaway user): 5 wrong passwords, then right password | 401 x5, then 429 | `[401,401,401,401,401]` then `429 Too many failed logins for this email.  Please try again in a few minutes.` | PASS |
| W3 | Same user, right password ~14 min after the 5th failure | 429 (still locked) | `429` (same message) | PASS |
| W4 | Same user, right password ~15 min 20 s after the 5th failure | 200 (lock expired) | `200` + token | PASS |

Row R6, M5 and Z.C are the three FAILs of the main run, explained next.
* **R6 FAIL**: `a@b` (no dot in the domain) was accepted by register with 201 although the docs call the field `format: email`. The user was created, tracked and deleted.
* **M5 FAIL**: `PUT /api/users/me {"name": ""}` returned 200 and stored an empty name, whereas register rejects an empty name with 422.
* **Z.C FAIL (harness expectation, fixed in the script after the run)**: after the throwaway lockout user was deleted, logging in as that email gave `429`, not `401`.
  The lockout belongs to the email address and outlives the account. The script now accepts 401 or 429 there. In the separate lockout-expiry run (W) the post-delete check passed (401 once the lock had expired).

## App bugs (not fixed, file:line)

**None found that break against the real responses.** All 70 tests pass (`flutter test`) including the 28 new ones in `test/live_shapes/` that replay the
real status codes and bodies (200, 201, 400, 401, 403, 404, 405, 409, 422, 429, empty and HTML error bodies, network failure), and `flutter analyze` is clean.
Cosmetic or low-impact observations only:

1. `lib/auth_api.dart:123` (`case 429 when login`): the message says "locked for 15 minutes" then appends the server text in brackets,
   `(Too many failed logins for this email.  Please try again in a few minutes.)`. The 15 minutes is accurate (W3/W4 measured it) but the appended text
   is vaguer and contradicts the tone; it also contains a double space. Dropping `$detail` for this case would be cleaner.
2. `lib/auth_api.dart:121` (`case 422`): the API joins several validation problems into one string separated by **two spaces**
   (`The name field is required.  The email field is required.`). No 422 ever carried the `errors` map that `_errorText` also handles, so that branch is untested against reality (harmless).
3. `lib/auth_api.dart:85` (`isBadSession`): relies on the 401 message not containing the word "apikey". True today: real bad-token messages are `Invalid or expired auth token. Log in again.`
   and `Unauthorized. Log in and send the header "Authorization: Bearer <token>".` (K2, M2). If the API ever changes that wording the app would mis-classify; there is no status or code field to rely on.
4. Not an app bug, but worth knowing: the lock outlives the account (Z.C), so deleting a locked-out account and re-registering the same address still cannot log in until the 15 minutes pass.

The app's client-side guards (non-empty name, 8 to 72 password) are stricter than the API in places (API accepts an empty name on update, M5; counts differ for non-BMP characters, untested), so the app never exposes the M5 inconsistency.

## API bugs or doc mismatches

1. **`a@b` is accepted as an email** (R6, 201). Docs say `format: email`; the real rule is looser than most people expect. Low severity.
2. **Empty name accepted on update, rejected on register** (M5 vs R10). Inconsistent validation. Also `PUT /api/users/me` with `{}` returns 200 and changes nothing (M7); fine but undocumented.
3. **Changing or omitting `current_password`:** docs list only `403 current_password is wrong`. Real behaviour: wrong value gives 403 (M9, M10), a **missing** value gives **422**
   `The current password field is required when email / password is present.` (M8, M11). Docs do list 422 generally, so this is a minor gap.
4. **Lockout response**: `429` has **no `Retry-After` header** and the message says "a few minutes", while the docs and the measured behaviour are exactly 15 minutes (still locked at 14 min, free at 15 min 20 s).
   The lock is per email, case-insensitive (X5), blocks the right password too (X4), does not affect other users (X6), does **not** revoke an already issued token (X7: it still returned 200),
   applies to unknown emails exactly like real ones (X8: 401 x5 then 429, so no enumeration leak), and outlives deleting the account (Z.C).
   Anyone can lock any known email by sending 5 wrong passwords (inherent to per-email lockout; worth a doc line).
5. **Failed-login counter resets on success** (X1): 4 wrong, right, 4 wrong, right never locked. Not documented, sensible.
6. **Rate-limit headers are misleading**: `X-RateLimit-Limit: 20` on every response, but `X-RateLimit-Remaining` is not monotonic (7 to 19) and ~55 requests/minute were never throttled.
   Either the counters are per worker, or they are not enforced, or they describe the shared demo key's other traffic. The docs mention no general rate limit at all.
7. **Changing the email does not log out other sessions** (M15b: the second session still returned 200). Docs only promise that for a password change (which does work: M18, and the changing session stays logged in, M19). Fine, but the "new email must be verified again" step does not restrict anything: `email_verified` just flips to false.
8. **No password-strength policy beyond length**: `12345678` was accepted (M22). Matches the docs (they only state 8 to 72).
9. **Malformed JSON** (`{not json`) gets `422 The name field is required...`, i.e. it is treated as an empty body, not a 400 (R15). Validation errors still come back as JSON without an `Accept` header (R16).
10. CORS is fine for the sample: preflight for PUT and DELETE returns 200 with `Access-Control-Allow-Origin: *`, methods `POST, GET, OPTIONS, PUT, DELETE`, headers `Content-Type, Authorization, X-Requested-With, Origin` (C1, C2). The preflight body is `{"method":"OPTIONS"}`. I did not drive a real browser, only inspected headers.
11. The not-found body is `{"message":"Not a valid api route - not found."}` (404); an unsupported method gives 405 with an empty body.

## Not tested and why

* **Verify email, finish password reset** (`/email/verify` success, `/users/reset` success): need the emailed code and I have no inbox. Only the wrong-code `400` paths (E4, E9) and missing-field `422` paths (E5, E10) were exercised. Consequently also untested: code expiry (15 min), the 5-wrong-attempts limit, "reset logs out every session / counts as verified".
* **`409` on send-code for an already verified email**, and anything else needing a verified address (the email is never verified here), including admin behaviour of the developer account.
* **`403` register when the key has 25 users**: not triggered on purpose (it would fill the shared demo key). The docs list it; the app's `isUserCapReached` is covered only by the existing docs-based tests, not by a captured real body.
* **`403` login for a disabled account**: needs an admin route to disable a user; `PUT /api/users/{id}` was not touched. The admin routes `GET /api/users` (only the 403 for a normal user, M23), `GET/PUT/DELETE /api/users/{id}` are not used by the app.
* **`429` on forgot-password (daily limit of 20 emails per key)**: not triggered on purpose (the key is shared). `forgot` twice in a row for the same registered email within a minute was not tested.
* **Token lifetime** (30 days): only `expires_at` was read (`2026-11-30`, 30 days after issue).
* **Running the real Flutter web UI against the live API in a browser**. Only `AuthApi` was replayed with captured responses; the UI is covered by the existing mocked widget tests.
* **Concurrency**, large bodies, unusual Unicode in emails or passwords, SQL/script payloads beyond the one HTML/emoji name (M4 round-tripped unchanged).
* **User count readback** (admin-only). Cleanup was confirmed indirectly, see above.

## Harness caveats

* The main run used the first version of the script. Afterwards I (a) fixed a redaction ordering bug in the *saved transcript* (tokens of users that were already deleted had been written to a scratch file outside the repo, which I deleted),
  (b) relaxed the Z-check to accept 401 or 429, (c) added `--lockout-only` and `--keys-only` modes and the K6 to K8 checks. The full path was **not re-run** after those edits because the 6-user budget was spent.
  The table above is copied from the console log of that main run, except for the K6 to K8 and W rows, which come from their own runs. The console log shows each response body trimmed to 140 characters.
* "Observe" rows always pass; they are findings, not assertions.
