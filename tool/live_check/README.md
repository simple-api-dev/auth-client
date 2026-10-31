# Live check of the Auth API paths used by this sample

`live_check.py` calls every endpoint that `lib/auth_api.dart` uses against the real
`https://auth.simpleapi.dev`, and prints PASS/FAIL per check. Results of the last run are
in [`REPORT.md`](REPORT.md). It is a snapshot of what was tried, **not** proof that the API is bug free.

## Run it

Python 3.9+ and nothing else (standard library only). From the repo root:

```bash
SIMPLEAPI_KEY=<your Auth API key> python3 tool/live_check/live_check.py
```

Add `--lockout-only` to run just the 15-minute lockout-expiry test (about 16 minutes, 1 user):

```bash
SIMPLEAPI_KEY=<your Auth API key> python3 tool/live_check/live_check.py --lockout-only
```

Output goes to the console and to `tool/live_check/out/` (`results.md`, `transcript.json`; git-ignored,
and redacted: key, tokens and generated passwords are replaced by `<redacted>`).

## Safety

* The key is read only from the `SIMPLEAPI_KEY` environment variable and is never written anywhere.
* Test passwords are generated at run time, never stored.
* The key's free tier holds 25 users and the demo key is shared. The script registers at most 6 users
  per run (`MAX_USERS`, normally 4; 1 with `--lockout-only`), uses
  `simpleapi-sample-apps+<random>@agentmail.to` addresses, and deletes each one with
  `DELETE /api/users/me` at the end (also on errors). If a delete fails it says so, so you can clean up.
* Requests are paced to at most one per second, and the script waits out the rate-limit window (`X-RateLimit-Remaining` low) or a `429 Rate limit exceeded` (`Retry-After`) instead of failing; `--ratelimit-only` runs just the rate-limit test (no users).
* It sends real emails: one verification code and two password-reset requests per run (the API allows
  20 reset/verification emails per day per key, shared with everyone using the key). It never
  completes an emailed-code step.
* The lockout is exercised only on a throwaway user created for it.

Real responses captured by the script are replayed through the app in
`test/live_shapes/live_shapes_test.dart` (run with `flutter test`).
