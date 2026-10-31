#!/usr/bin/env python3
"""Live check of the SimpleApi Auth API paths used by lib/auth_api.dart.

Run (see README.md):  SIMPLEAPI_KEY=<key> python3 tool/live_check/live_check.py

Safety rules built in:
  * the key is read ONLY from the SIMPLEAPI_KEY environment variable;
  * every secret (key, tokens, generated passwords) is redacted from all output;
  * at most MAX_USERS users are ever registered; each is deleted at the end;
  * requests are paced (>= 1.0 s apart) and 429 rate-limit answers are backed off.
Standard library only.
"""
import argparse
import json
import os
import re
import secrets
import ssl
import sys
import time
import urllib.error
import urllib.request

BASE = os.environ.get("SIMPLEAPI_BASE", "https://auth.simpleapi.dev")
MAX_USERS = 6
PACE = 1.0
ORIGIN = "https://simple-api-dev.github.io"
KEY = os.environ.get("SIMPLEAPI_KEY", "").strip()

secrets_to_hide = set()
results = []      # one dict per check
transcript = []   # redacted request/response log
calls = 0
last_call = 0.0
throttles = []    # observed generic throttle events
rl_state = {"remaining": None, "reset": None}   # last X-RateLimit-* seen, to avoid hitting the limit by accident
rl_log = []       # (call number, status, remaining, reset) for every call
users = {}        # label -> dict(email, password, tokens[])
registered = 0


def hide(s):
    secrets_to_hide.add(s)


def redact(text):
    text = re.sub(r"\b[0-9a-f]{64}\b", "<redacted>", str(text))  # token-shaped strings
    for s in sorted(secrets_to_hide, key=len, reverse=True):
        if s:
            text = text.replace(s, "<redacted>")
    return text


def rnd():
    return secrets.token_hex(5)


def new_email():
    return f"simpleapi-sample-apps+{rnd()}@agentmail.to"


def new_password(n=16):
    p = secrets.token_urlsafe(2 * n)[:n]
    hide(p)
    return p


class Resp:
    def __init__(self, status, headers, text):
        self.status = status
        self.headers = {k.lower(): v for k, v in headers.items()}
        self.text = text
        try:
            self.json = json.loads(text) if text else None
        except ValueError:
            self.json = None

    @property
    def message(self):
        j = self.json
        return j.get("message", "") if isinstance(j, dict) else ""

    def short(self):
        body = self.text if len(self.text) < 300 else self.text[:300] + "..."
        return f"{self.status} {redact(body)}"


class Abort(Exception):
    pass


def call(method, path, body=None, token=None, key=True, accept=True, raw=None,
         extra_headers=None, query_extra="", expect_lockout=False, no_wait=False, retry_rate_limit=True):
    """One paced HTTP call. Returns Resp. Backs off on generic throttling."""
    global calls, last_call
    for attempt in range(4):
        wait = PACE - (time.time() - last_call)
        if wait > 0:
            time.sleep(wait)
        # Stay under the documented per-IP limit: when the last answer said at most 1 request is left in the
        # window, wait for the window to end instead of provoking a 429 (the dedicated RL test provokes one on purpose).
        if not no_wait and rl_state["remaining"] is not None and rl_state["remaining"] <= 1 \
                and rl_state["reset"] and rl_state["reset"] > time.time():
            sl = rl_state["reset"] - time.time() + 1
            print(f"  . rate-limit window nearly used; waiting {sl:.0f}s", flush=True)
            time.sleep(sl)
            rl_state["remaining"] = None
        url = BASE + path + ("?apikey=" + KEY if key else "?") + query_extra
        url = url.rstrip("?")
        headers = {}
        if accept:
            headers["Accept"] = "application/json"
        data = None
        if raw is not None:
            data = raw.encode()
            headers["Content-Type"] = "application/json"
        elif body is not None:
            data = json.dumps(body).encode()
            headers["Content-Type"] = "application/json"
        if token:
            headers["Authorization"] = "Bearer " + token
        headers.update(extra_headers or {})
        req = urllib.request.Request(url, data=data, method=method, headers=headers)
        last_call = time.time()
        calls += 1
        try:
            with urllib.request.urlopen(req, timeout=30, context=ssl.create_default_context()) as r:
                resp = Resp(r.status, dict(r.headers), r.read().decode("utf-8", "replace"))
        except urllib.error.HTTPError as e:
            resp = Resp(e.code, dict(e.headers), e.read().decode("utf-8", "replace"))
        transcript.append({
            "n": calls, "method": method, "path": path,
            "request_body": json.loads(redact(json.dumps(body))) if body is not None else raw,
            "status": resp.status, "response_body": redact(resp.text)[:1500],
            "headers": {k: redact(v) for k, v in resp.headers.items()
                        if k in ("retry-after", "x-ratelimit-limit", "x-ratelimit-remaining",
                                 "x-ratelimit-reset", "content-type", "access-control-allow-origin",
                                 "access-control-allow-methods", "access-control-allow-headers",
                                 "access-control-max-age", "vary")},
        })
        h = resp.headers
        rem = int(h["x-ratelimit-remaining"]) if h.get("x-ratelimit-remaining", "").lstrip("-").isdigit() else None
        rst = int(h["x-ratelimit-reset"]) if h.get("x-ratelimit-reset", "").isdigit() else None
        rl_log.append((calls, resp.status, rem, rst, path))
        rl_state["remaining"], rl_state["reset"] = rem, rst
        msg = resp.message.lower()
        throttled = resp.status == 429 and retry_rate_limit and ("throttle" in msg or msg.startswith("rate limit"))
        if throttled:
            ra = resp.headers.get("retry-after", "")
            throttles.append({"after_calls": calls, "path": path, "retry_after": ra,
                              "message": resp.message})
            if attempt == 3:
                raise Abort(f"still throttled after retries at call {calls}")
            sleep = min(int(ra) if ra.isdigit() else 30, 120) + 1
            print(f"  ! throttled (429 {resp.message!r}) after {calls} calls, Retry-After={ra!r}; sleeping {sleep}s", flush=True)
            time.sleep(sleep)
            continue
        return resp
    raise Abort("unreachable")


def check(cid, what, expected, resp, ok, note=""):
    actual = resp.short() if isinstance(resp, Resp) else str(resp)
    results.append({"id": cid, "what": what, "expected": expected,
                    "actual": actual, "pass": bool(ok), "note": note})
    print(f"[{'PASS' if ok else 'FAIL'}] {cid} {what} | expected {expected} | {actual[:140]}", flush=True)
    return resp


def status_check(cid, what, expected, resp, *statuses, extra=True, note=""):
    return check(cid, what, expected, resp, resp.status in statuses and bool(extra), note)


USER_FIELDS = {"id": int, "name": str, "email": str, "email_verified": bool,
               "admin": bool, "enabled": bool, "created_at": str}


def user_shape_ok(u):
    return isinstance(u, dict) and all(isinstance(u.get(k), t) for k, t in USER_FIELDS.items())


def register(label, name="Live Check", email=None, password=None):
    """Budgeted register. Records the user for cleanup whenever a user is created."""
    global registered
    if registered >= MAX_USERS:
        raise Abort("user budget exhausted")
    email = email or new_email()
    password = password or new_password()
    r = call("POST", "/api/users/register", {"name": name, "email": email, "password": password})
    if r.status in (200, 201) and isinstance(r.json, dict) and r.json.get("token"):
        registered += 1
        hide(r.json["token"])
        users[label] = {"email": email, "password": password, "tokens": [r.json["token"]],
                        "deleted": False}
    return r, email, password


def token_of(r):
    return r.json.get("token") if isinstance(r.json, dict) else None


def login(email, password):
    r = call("POST", "/api/users/login", {"email": email, "password": password})
    t = token_of(r)
    if t:
        hide(t)
    return r


def cleanup():
    print("\n== cleanup: deleting every user created ==", flush=True)
    for label, u in users.items():
        if u["deleted"]:
            continue
        done = False
        for t in list(u["tokens"]):
            r = call("DELETE", "/api/users/me", {"password": u["password"]}, token=t)
            if r.status == 200:
                done = True
                break
        if not done:
            r = login(u["email"], u["password"])
            t = token_of(r)
            if t:
                r = call("DELETE", "/api/users/me", {"password": u["password"]}, token=t)
                done = r.status == 200
        u["deleted"] = done
        print(f"  cleanup {label}: {'deleted' if done else 'NOT DELETED (manual cleanup needed)'}", flush=True)


def key_checks():
    """Checks that create no users (safe to run any number of times)."""
    r = call("GET", "/api/users/me", key=False)
    status_check("K1", "GET /me with no apikey and no token", "401", r, 401,
                 note="App's ApiException.isBadKey needs 'apikey' in the message: " + r.message)
    r = call("GET", "/api/users/me", token="not-a-token")
    status_check("K2", "GET /me with valid apikey, garbage token", "401 (must NOT mention apikey)", r, 401,
                 extra="apikey" not in r.message.lower(),
                 note="message=" + repr(r.message))
    bad = call("POST", "/api/users/login", {"email": "a@b.test", "password": "x" * 8}, key=False)
    status_check("K3", "login with no apikey", "401 mentioning apikey", bad, 401,
                 extra="apikey" in bad.message.lower(), note="message=" + repr(bad.message))
    r = call("GET", "/api/users/me", key=False, query_extra="apikey=00000000-0000-0000-0000-000000000000")
    status_check("K4", "GET /me with unknown apikey (well-formed)", "401 mentioning apikey", r, 401,
                 extra="apikey" in r.message.lower(), note="message=" + repr(r.message))
    r = call("GET", "/api/users/me", key=False, query_extra="apikey=not-a-uuid")
    status_check("K5", "GET /me with malformed apikey", "401 mentioning apikey", r, 401,
                 extra="apikey" in r.message.lower(), note="message=" + repr(r.message))

    # CORS preflight (the app is Flutter web calling the API cross-origin)
    r = call("OPTIONS", "/api/users/me", extra_headers={
        "Origin": ORIGIN, "Access-Control-Request-Method": "PUT",
        "Access-Control-Request-Headers": "authorization,content-type,accept"})
    ah = r.headers.get("access-control-allow-headers", "").lower()
    am = r.headers.get("access-control-allow-methods", "").upper()
    ao = r.headers.get("access-control-allow-origin", "")
    ok = r.status in (200, 204) and ao in ("*", ORIGIN) and all(
        h in ah or ah.strip() == "*" for h in ("authorization", "content-type")) and (
        "PUT" in am or am.strip() == "*") 
    check("C1", "CORS preflight for PUT /me from the Pages origin", "2xx, allow-origin, allow Authorization+Content-Type+PUT", r, ok,
          note=f"allow-origin={ao!r} allow-methods={am!r} allow-headers={ah!r}")
    r = call("OPTIONS", "/api/users/me", extra_headers={
        "Origin": ORIGIN, "Access-Control-Request-Method": "DELETE",
        "Access-Control-Request-Headers": "authorization,content-type"})
    am = r.headers.get("access-control-allow-methods", "").upper()
    check("C2", "CORS preflight for DELETE /me", "2xx and DELETE allowed", r,
          r.status in (200, 204) and ("DELETE" in am or am.strip() == "*"), note=f"allow-methods={am!r}")

    # AuthApi.checkKey(): GET /api/keys/check; 200 {"valid": true} = accepted, 401 = rejected
    r = call("GET", "/api/keys/check")
    status_check("K6", "checkKey(): GET /keys/check with a GOOD key", "200 {\"valid\":true}", r, 200,
                 extra=r.json == {"valid": True}, note="body=" + redact(r.text))
    r = call("GET", "/api/keys/check", key=False, query_extra="apikey=00000000-0000-0000-0000-000000000000")
    status_check("K7", "checkKey(): GET /keys/check with a BAD key", "401 mentioning apikey", r, 401,
                 extra="apikey" in r.message.lower(), note="message=" + repr(r.message))
    r = call("GET", "/api/keys/check", key=False)
    status_check("K8", "checkKey(): GET /keys/check with NO key", "401 mentioning apikey", r, 401,
                 extra="apikey" in r.message.lower(), note="message=" + repr(r.message))
    # API fix not deployed yet when this was written: the 401 must not echo the key text it was sent
    probe = "00000000-0000-0000-0000-000000000000"
    r = call("GET", "/api/keys/check", key=False, query_extra="apikey=" + probe)
    status_check("K9", "invalid apikey 401 does not echo the key text", "401, key not in message", r, 401,
                 extra=probe not in r.text, note="message=" + repr(r.message))
    r = call("POST", "/api/users/login", raw="{not json")
    status_check("K10", "malformed JSON with a GOOD key", "400", r, 400, note="message=" + repr(r.message))
    r = call("POST", "/api/users/login", raw="{not json", key=False, query_extra="apikey=" + probe)
    status_check("K11", "malformed JSON with a BAD key (key is checked first)", "401", r, 401, note="message=" + repr(r.message))
    r = call("POST", "/api/users/login", raw='"just a string"')
    status_check("K12", "valid JSON that is not an object", "400", r, 400, note="message=" + repr(r.message))
    r = call("POST", "/api/users/login", {})
    status_check("K13", "empty JSON object is still validated", "422", r, 422, note="message=" + repr(r.message))


def rate_limit_test():
    """Documented: 20 requests/minute per client IP, fixed 60 s window, X-RateLimit-* on every response, 429 + Retry-After
    past the limit. Starts right after a window reset, then sends GET /api/keys/check once a second (creates no users)."""
    r = call("GET", "/api/keys/check", no_wait=True)
    reset = rl_state["reset"]
    if reset and reset > time.time():
        sl = reset - time.time() + 1.5
        print(f"  . waiting {sl:.0f}s for a fresh rate-limit window", flush=True)
        time.sleep(sl)
    seq = []
    first429 = None
    for i in range(1, 24):
        r = call("GET", "/api/keys/check", no_wait=True, retry_rate_limit=False)
        h = r.headers
        seq.append((r.status, h.get("x-ratelimit-limit"), h.get("x-ratelimit-remaining"), h.get("x-ratelimit-reset")))
        if r.status == 429:
            first429 = (i, r)
            break
    ok200 = [x for x in seq if x[0] == 200]
    lim = {x[1] for x in seq}
    check("RL1", "X-RateLimit-Limit and -Reset present on every response", "Limit=20, Reset a unix time", str(seq[:3]) + " ...",
          lim == {"20"} and all(x[3] and x[3].isdigit() for x in seq), note="limits=" + str(lim))
    rems = [int(x[2]) for x in ok200 if (x[2] or "").lstrip("-").isdigit()]
    resets = {x[3] for x in ok200}
    mono = all(b <= a for a, b in zip(rems, rems[1:]))
    check("RL2", "X-RateLimit-Remaining only goes down within a window", "non-increasing, one Reset value", f"remaining={rems} resets={sorted(resets)}",
          mono and len(resets) == 1, note="counts down by exactly 1 each time: " + str(all(a - b == 1 for a, b in zip(rems, rems[1:]))))
    if first429:
        i, rr = first429
        check("RL3", "a 429 fires at the documented limit (20/min)", "first 429 on request 21 of the window", f"429 on request {i}: {rr.short()[:160]}",
              i == 21 and len(ok200) == 20, note=f"headers retry-after={rr.headers.get('retry-after')} limit={rr.headers.get('x-ratelimit-limit')} remaining={rr.headers.get('x-ratelimit-remaining')} reset={rr.headers.get('x-ratelimit-reset')}")
        check("RL4", "429 is JSON with message and Retry-After 1..60", "json message, Retry-After seconds", rr,
              isinstance(rr.json, dict) and "message" in rr.json and rr.headers.get("retry-after", "").isdigit()
              and 1 <= int(rr.headers["retry-after"]) <= 60, note="message=" + repr(rr.message))
        wait = int(rr.headers.get("retry-after", "60")) + 1
        print(f"  . sleeping {wait}s until the window ends", flush=True)
        time.sleep(wait)
        r = call("GET", "/api/keys/check", no_wait=True)
        status_check("RL5", "allowed again after Retry-After", "200", r, 200)
    else:
        check("RL3", "a 429 fires at the documented limit (20/min)", "first 429 on request 21 of the window", f"no 429 in {len(seq)} requests", False,
              note="statuses=" + str([x[0] for x in seq]))
    rl_state["remaining"] = None


def run(args):
    rate_limit_test()
    key_checks()
    global registered
    print("\n== register ==", flush=True)
    r, a_email, a_pw = register("A", name="Alice Live", password=new_password(8))  # exactly 8 chars
    assert len(a_pw) == 8
    ok = r.status == 201 and isinstance(r.json, dict) and r.json.get("token") and user_shape_ok(r.json.get("user"))
    check("R1", "register valid (8-char password = documented minimum)", "201 + token + user", r, ok,
          note="top-level keys=" + str(sorted(r.json.keys()) if isinstance(r.json, dict) else None)
          + " user keys=" + str(sorted((r.json or {}).get("user", {}).keys()) if isinstance(r.json, dict) else None))
    if "A" not in users:
        raise Abort("cannot continue without user A")
    j = r.json
    check("R2", "register response user fields match the app's User.fromJson",
          "id int, name, email, email_verified false, admin false, enabled true, created_at str",
          r, user_shape_ok(j["user"]) and j["user"]["email_verified"] is False and j["user"]["admin"] is False
          and j["user"]["enabled"] is True and j["user"]["email"] == a_email,
          note="expires_at=" + str(j.get("expires_at")) + " created_at=" + str(j["user"].get("created_at")))
    tokA1 = users["A"]["tokens"][0]

    r, _, _ = register("dupe", name="Dupe", email=a_email, password=new_password())
    status_check("R3", "register duplicate email", "409", r, 409, note="message=" + repr(r.message))
    r, _, _ = register("dupe2", name="Dupe", email=a_email.upper(), password=new_password())
    status_check("R4", "register same email in different case", "409 (emails are case-insensitive)", r, 409,
                 note="message=" + repr(r.message))
    for cid, what, body in [
        ("R5", "register bad email (no @)", {"name": "X", "email": "not-an-email", "password": new_password()}),
        ("R6", "register bad email (no domain dot)", {"name": "X", "email": "a@b", "password": new_password()}),
        ("R7", "register password 7 chars", {"name": "X", "email": new_email(), "password": new_password(7)}),
        ("R8", "register password 73 chars (max is 72)", {"name": "X", "email": new_email(), "password": new_password(73)}),
        ("R9", "register missing name", {"email": new_email(), "password": new_password()}),
        ("R10", "register empty name", {"name": "", "email": new_email(), "password": new_password()}),
        ("R11", "register name 256 chars (max 255)", {"name": "n" * 256, "email": new_email(), "password": new_password()}),
        ("R12", "register missing password", {"name": "X", "email": new_email()}),
        ("R13", "register missing email", {"name": "X", "password": new_password()}),
        ("R14", "register empty body", {}),
    ]:
        r = call("POST", "/api/users/register", body)
        created = r.status in (200, 201)
        if created:  # should not happen; keep the budget honest and clean up
            globals()["registered"] += 1
            t = token_of(r)
            if t:
                hide(t)
                users["stray-" + cid] = {"email": body.get("email"), "password": body.get("password"),
                                         "tokens": [t], "deleted": False}
        status_check(cid, what, "422", r, 422, note="message=" + repr(r.message) + " errors=" + json.dumps(r.json.get("errors") if isinstance(r.json, dict) else None))
    r = call("POST", "/api/users/register", raw="{not json")
    status_check("R15", "register malformed JSON body", "400 (was 422 before the API fix)", r, 400, note="message=" + repr(r.message))
    r = call("POST", "/api/users/register", {"name": "X", "email": "bad", "password": "short"}, accept=False)
    check("R16", "validation error WITHOUT Accept header (the app always sends Accept)", "422 JSON",
          r, r.status == 422 and r.json is not None, note="status=" + str(r.status))

    # ---- 2. login ------------------------------------------------------------
    print("\n== login ==", flush=True)
    r = login(a_email, a_pw)
    check("L1", "login right password", "200 + token + user (new token)", r,
          r.status == 200 and token_of(r) and user_shape_ok(r.json.get("user")) and token_of(r) != tokA1)
    tokA2 = token_of(r)
    users["A"]["tokens"].append(tokA2)
    r = login(a_email, new_password())
    status_check("L2", "login wrong password", "401", r, 401, note="message=" + repr(r.message))
    r = login(a_email.upper(), a_pw)
    check("L3", "login with UPPERCASE email", "200 (case-insensitive)", r, r.status == 200)
    if token_of(r):
        users["A"]["tokens"].append(token_of(r))
    r = login(new_email(), a_pw)
    status_check("L4", "login unknown email", "401, same message as wrong password", r, 401,
                 note="message=" + repr(r.message))
    r = call("POST", "/api/users/login", {"email": "bad", "password": "x"})
    status_check("L5", "login with malformed email", "422 (or 401)", r, 422, 401, note="message=" + repr(r.message))
    r = call("POST", "/api/users/login", {"email": a_email})
    status_check("L6", "login missing password", "422", r, 422, note="message=" + repr(r.message))

    # ---- 3. me ---------------------------------------------------------------
    print("\n== /me ==", flush=True)
    r = call("GET", "/api/users/me", token=tokA1)
    check("M1", "GET /me", "200 + user", r, r.status == 200 and user_shape_ok(r.json) and r.json["email"] == a_email)
    r = call("GET", "/api/users/me")
    status_check("M2", "GET /me without token (valid apikey)", "401", r, 401, extra="apikey" not in r.message.lower(),
                 note="message=" + repr(r.message))
    r = call("PUT", "/api/users/me", {"name": "Alice Renamed"}, token=tokA1)
    check("M3", "PUT /me change name", "200 + new name", r, r.status == 200 and r.json.get("name") == "Alice Renamed")
    r = call("PUT", "/api/users/me", {"name": "Zoë 😀 ñ <b>x</b> & \"q\""}, token=tokA1)
    check("M4", "PUT /me unicode / HTML in name round-trips unchanged", "200 + identical name", r,
          r.status == 200 and r.json.get("name") == "Zoë 😀 ñ <b>x</b> & \"q\"", note="name=" + repr((r.json or {}).get("name")))
    r = call("PUT", "/api/users/me", {"name": ""}, token=tokA1)
    status_check("M5", "PUT /me empty name", "422", r, 422, note="message=" + repr(r.message))
    r = call("PUT", "/api/users/me", {"name": "n" * 256}, token=tokA1)
    status_check("M6", "PUT /me name 256 chars", "422", r, 422)
    r = call("PUT", "/api/users/me", {"name": "   "}, token=tokA1)
    status_check("M5b", "PUT /me blank (spaces) name", "422", r, 422, note="message=" + repr(r.message))
    r = call("PUT", "/api/users/me", {"name": None}, token=tokA1)
    status_check("M5c", "PUT /me null name", "422", r, 422, note="message=" + repr(r.message))
    r = call("PUT", "/api/users/me", {"password": "", "current_password": a_pw}, token=tokA1)
    status_check("M5d", "PUT /me empty password", "422", r, 422, note="message=" + repr(r.message))
    r = call("GET", "/api/users/me", token=tokA1)
    check("M5e", "...and nothing was changed by those rejected updates", "name still Alice Live", r,
          r.status == 200 and (r.json or {}).get("name") == "Alice Live", note="body=" + redact(r.text)[:120])
    r = call("PUT", "/api/users/me", {}, token=tokA1)
    check("M7", "PUT /me empty body", "200 unchanged or 422", r, r.status in (200, 422), note="status=" + str(r.status))
    r = call("PUT", "/api/users/me", {"name": "Alice Live"}, token=tokA1)
    r = call("PUT", "/api/users/me", {"email": "someone@example.test"}, token=tokA1)
    status_check("M8", "PUT /me change email WITHOUT current_password", "403 or 422 (docs: current password required)", r, 403, 422,
                 note="message=" + repr(r.message))
    r2 = call("GET", "/api/users/me", token=tokA1)
    check("M8b", "  ...and the email was NOT changed", "email unchanged", r2, r2.json and r2.json["email"] == a_email)
    r = call("PUT", "/api/users/me", {"email": new_email(), "current_password": new_password()}, token=tokA1)
    status_check("M9", "PUT /me change email with WRONG current_password", "403", r, 403, note="message=" + repr(r.message))
    r = call("PUT", "/api/users/me", {"password": new_password(), "current_password": new_password()}, token=tokA1)
    status_check("M10", "PUT /me change password with WRONG current_password", "403", r, 403, note="message=" + repr(r.message))
    r = call("PUT", "/api/users/me", {"password": new_password()}, token=tokA1)
    status_check("M11", "PUT /me change password WITHOUT current_password", "403 or 422", r, 403, 422, note="message=" + repr(r.message))
    r = call("PUT", "/api/users/me", {"password": new_password(7), "current_password": a_pw}, token=tokA1)
    status_check("M12", "PUT /me new password too short (7)", "422", r, 422, note="message=" + repr(r.message))
    r = call("PUT", "/api/users/me", {"email": "bad", "current_password": a_pw}, token=tokA1)
    status_check("M13", "PUT /me invalid new email", "422", r, 422, note="message=" + repr(r.message))
    r = call("PUT", "/api/users/me", {"email": "a@b", "current_password": a_pw}, token=tokA1)
    status_check("M13b", "PUT /me new email a@b (no dot in domain)", "422", r, 422, note="message=" + repr(r.message))

    # user B: used for the 409-on-update check and the logout tests
    r, b_email, b_pw = register("B", name="Bob Live")
    status_check("B0", "register user B", "201", r, 201)
    if "B" not in users:
        raise Abort("cannot create user B")
    r = call("PUT", "/api/users/me", {"email": b_email, "current_password": a_pw}, token=tokA1)
    status_check("M14", "PUT /me change email to one already registered", "409", r, 409, note="message=" + repr(r.message))
    r = call("PUT", "/api/users/me", {"email": b_email.upper(), "current_password": a_pw}, token=tokA1)
    status_check("M14b", "PUT /me change email to existing one in other case", "409", r, 409, note="message=" + repr(r.message))

    a_new_email = new_email()
    r = call("PUT", "/api/users/me", {"email": a_new_email, "current_password": a_pw}, token=tokA1)
    check("M15", "PUT /me change email with right current_password", "200, new email, email_verified false", r,
          r.status == 200 and r.json.get("email") == a_new_email and r.json.get("email_verified") is False,
          note="user=" + redact(json.dumps(r.json)))
    if r.status == 200:
        users["A"]["email"] = a_new_email
        a_email = a_new_email
    r = call("GET", "/api/users/me", token=tokA2)
    check("M15b", "  ...other sessions after an EMAIL change", "documented only for password; observe", r, r.status in (200, 401),
          note="other session now " + str(r.status))
    r = login(users["A"]["email"], a_pw)
    check("M16", "login with the new email", "200", r, r.status == 200)
    if token_of(r):
        users["A"]["tokens"].append(token_of(r))

    # password change on A: sessions tokA1 (changer), tokA2 (other)
    r = call("GET", "/api/users/me", token=tokA2)
    if r.status != 200:   # refresh a second session if the email change killed it
        rr = login(a_email, a_pw)
        tokA2 = token_of(rr)
        users["A"]["tokens"].append(tokA2)
    old_pw = a_pw
    a_pw = new_password(72)
    r = call("PUT", "/api/users/me", {"password": a_pw, "current_password": old_pw}, token=tokA1)
    check("M17", "PUT /me change password to 72 chars (max) with right current_password", "200", r, r.status == 200,
          note="message=" + repr(r.message))
    if r.status == 200:
        users["A"]["password"] = a_pw
    else:
        a_pw = old_pw
    r = call("GET", "/api/users/me", token=tokA2)
    status_check("M18", "other session after password change", "401 (documented: logs out other sessions)", r, 401)
    r = call("GET", "/api/users/me", token=tokA1)
    check("M19", "changing session after password change", "200 (stays logged in) - docs say only OTHER sessions", r,
          r.status in (200, 401), note="status=" + str(r.status))
    r = login(a_email, old_pw)
    status_check("M20", "login with the OLD password", "401", r, 401)
    r = login(a_email, a_pw)
    check("M21", "login with the new 72-char password", "200", r, r.status == 200)
    if token_of(r):
        users["A"]["tokens"].append(token_of(r))
    tokA = token_of(r)
    r = call("PUT", "/api/users/me", {"password": "12345678", "current_password": a_pw}, token=tokA)
    if r.status == 200:
        a_pw_old, a_pw = a_pw, "12345678"
        users["A"]["password"] = a_pw
        check("M22", "PUT /me weak password '12345678'", "documented only min length 8; observe", r, True,
              note="ACCEPTED - no strength policy beyond length")
        # restore a random password so a trivial one never lingers
        newer = new_password()
        rr = call("PUT", "/api/users/me", {"password": newer, "current_password": a_pw}, token=tokA)
        if rr.status == 200:
            users["A"]["password"] = a_pw = newer
    else:
        check("M22", "PUT /me weak password '12345678'", "documented only min length 8; observe", r, True,
              note=f"rejected with {r.status}: {r.message}")
    r = call("GET", "/api/users", token=tokA)
    status_check("M23", "GET /api/users as a normal user (admin only)", "403", r, 403, note="message=" + repr(r.message))

    # ---- 4. email / reset emails (request half only) ------------------------
    print("\n== emails: request half only ==", flush=True)
    r = call("POST", "/api/users/me/email/send-code", token=tokA)
    status_check("E1", "email send-code (request half)", "200", r, 200, note="message=" + repr(r.message))
    r = call("POST", "/api/users/me/email/send-code", token=tokA)
    status_check("E2", "email send-code again immediately", "429 (one per minute)", r, 429, note="message=" + repr(r.message)
                 + " retry-after=" + r.headers.get("retry-after", "-"))
    r = call("POST", "/api/users/me/email/send-code")
    status_check("E3", "send-code without token", "401", r, 401)
    r = call("POST", "/api/users/me/email/verify", {"code": "000000"}, token=tokA)
    status_check("E4", "verify with a wrong code (400 path only)", "400", r, 400, note="message=" + repr(r.message))
    r = call("POST", "/api/users/me/email/verify", {}, token=tokA)
    status_check("E5", "verify with missing code", "422", r, 422, note="message=" + repr(r.message))
    r = call("POST", "/api/users/forgot", {"email": a_email})
    status_check("E6", "forgot-password for a registered email (request half)", "200", r, 200, note="message=" + repr(r.message))
    ra = r
    r = call("POST", "/api/users/forgot", {"email": new_email()})
    status_check("E7", "forgot-password for an UNKNOWN email", "200, identical to E6 (no enumeration)", r, 200,
                 extra=r.json == ra.json, note="E6=" + redact(ra.text) + " E7=" + redact(r.text))
    r = call("POST", "/api/users/forgot", {"email": "not-an-email"})
    status_check("E8", "forgot-password with invalid email", "422", r, 422, note="message=" + repr(r.message))
    r = call("POST", "/api/users/reset", {"email": a_email, "code": "000000", "password": new_password()})
    status_check("E9", "reset with a wrong code (400 path only)", "400", r, 400, note="message=" + repr(r.message))
    r = call("POST", "/api/users/reset", {"email": a_email})
    status_check("E10", "reset with missing fields", "422", r, 422, note="message=" + repr(r.message))

    # ---- 5. logout -----------------------------------------------------------
    print("\n== logout ==", flush=True)
    bt1 = users["B"]["tokens"][0]
    r = login(b_email, b_pw); bt2 = token_of(r); users["B"]["tokens"].append(bt2)
    r = login(b_email, b_pw); bt3 = token_of(r); users["B"]["tokens"].append(bt3)
    check("O0", "three concurrent sessions for B", "3 different tokens, all valid", r,
          len({bt1, bt2, bt3}) == 3 and None not in (bt1, bt2, bt3))
    r = call("POST", "/api/users/logout", token=bt1)
    check("O1", "logout this session (no body, as the app sends)", "200 + message", r, r.status == 200 and bool(r.message))
    r = call("GET", "/api/users/me", token=bt1)
    status_check("O2", "token reuse after logout (GET /me)", "401", r, 401, note="message=" + repr(r.message))
    r = call("POST", "/api/users/logout", token=bt1)
    status_check("O2b", "logout again with the dead token", "401", r, 401)
    r = call("PUT", "/api/users/me", {"name": "Zombie"}, token=bt1)
    status_check("O2c", "token reuse after logout (PUT /me)", "401", r, 401)
    r = call("GET", "/api/users/me", token=bt2)
    status_check("O3", "other session survives a single logout", "200", r, 200)
    r = call("POST", "/api/users/logout", {"all": True}, token=bt2)
    check("O4", 'logout {"all": true}', "200", r, r.status == 200, note="message=" + repr(r.message))
    for i, t in enumerate((bt2, bt3), 2):
        r = call("GET", "/api/users/me", token=t)
        status_check(f"O5.{i}", f"session {i} after logout-all", "401", r, 401)
    r = call("POST", "/api/users/logout", {"all": False})
    status_check("O6", "logout without token", "401", r, 401, note="message=" + repr(r.message))
    r = login(b_email, b_pw)
    check("O7", "can log in again after logout-all", "200", r, r.status == 200)
    if token_of(r):
        users["B"]["tokens"] = [token_of(r)]

    # ---- 6. lockout (throwaway user C only) ---------------------------------
    print("\n== lockout (throwaway user C) ==", flush=True)
    r, c_email, c_pw = register("C", name="Lockout Live")
    status_check("X0", "register throwaway user C", "201", r, 201)
    if "C" in users:
        # counter reset check: 4 wrong, 1 right, 4 wrong, 1 right
        seq = []
        for _ in range(4):
            seq.append(login(c_email, new_password()).status)
        rr = login(c_email, c_pw); seq.append(rr.status)
        for _ in range(4):
            seq.append(login(c_email, new_password()).status)
        rr2 = login(c_email, c_pw); seq.append(rr2.status)
        check("X1", "4 wrong, right, 4 wrong, right: success resets the failure counter",
              "[401x4,200,401x4,200] if reset (docs silent)", f"statuses={seq}", seq == [401] * 4 + [200] + [401] * 4 + [200],
              note="statuses=" + str(seq))
        if token_of(rr2):
            users["C"]["tokens"].append(token_of(rr2))
        # now the real lockout
        seq = []
        lock = None
        for i in range(1, 8):
            rr = login(c_email, new_password())
            seq.append(rr.status)
            if rr.status == 429 and lock is None:
                lock = rr
        check("X2", "7 consecutive wrong passwords: lockout after 5", "401x5 then 429", f"statuses={seq}",
              seq[:5] == [401] * 5 and all(s == 429 for s in seq[5:]), note="statuses=" + str(seq))
        if lock is not None:
            check("X3", "lockout response body / headers", "429, Retry-After 1..900, message says 15 minutes", lock,
                  lock.status == 429 and lock.headers.get("retry-after", "").isdigit()
                  and 1 <= int(lock.headers["retry-after"]) <= 900 and "15 minutes" in lock.message, note="message=" + repr(lock.message) + " retry-after=" + repr(lock.headers.get("retry-after"))
                  + " body=" + redact(lock.text))
        rr = login(c_email, c_pw)
        status_check("X4", "RIGHT password while locked", "429 (still locked)", rr, 429, note="message=" + repr(rr.message))
        rr = login(c_email.upper(), c_pw)
        status_check("X5", "RIGHT password, UPPERCASE email, while locked", "429 (lock is case-insensitive)", rr, 429)
        rr = login(a_email, a_pw)
        check("X6", "other user can still log in while C is locked", "200", rr, rr.status == 200)
        if token_of(rr):
            users["A"]["tokens"].append(token_of(rr))
        rr = call("GET", "/api/users/me", token=users["C"]["tokens"][0])
        check("X7", "existing token of the locked user", "observe (docs silent)", rr, rr.status in (200, 401),
              note="status=" + str(rr.status))
        # lockout on an unknown email (enumeration side channel?)
        ghost = new_email()
        gseq = [login(ghost, new_password()).status for _ in range(7)]
        check("X8", "7 wrong passwords for an UNKNOWN email", "if 401 throughout, no existence leak; if 429 from the 6th, same as real",
              f"statuses={gseq}", True, note="statuses=" + str(gseq) +
              (" -> unknown emails are locked exactly like real ones (no enumeration)" if gseq[5:] == [429, 429] else
               " -> unknown emails are NOT locked: 429 reveals the email exists (enumeration side channel)" if gseq == [401] * 7 else ""))
        if args.wait_lockout:
            print("  waiting 15m05s to test lockout expiry...", flush=True)
            time.sleep(15 * 60 + 5)
            rr = login(c_email, c_pw)
            check("X9", "login after the 15-minute lockout", "200", rr, rr.status == 200, note="status=" + str(rr.status))
            if token_of(rr):
                users["C"]["tokens"].append(token_of(rr))

    # ---- 7. delete -----------------------------------------------------------
    print("\n== delete ==", flush=True)
    r = call("DELETE", "/api/users/me", {"password": new_password()}, token=users["B"]["tokens"][0])
    status_check("D1", "DELETE /me wrong password", "403", r, 403, note="message=" + repr(r.message))
    r = call("DELETE", "/api/users/me", {}, token=users["B"]["tokens"][0])
    status_check("D2", "DELETE /me missing password", "422 (or 403)", r, 422, 403, note="message=" + repr(r.message))
    r = call("DELETE", "/api/users/me", {"password": b_pw})
    status_check("D3", "DELETE /me without token", "401", r, 401)
    r = call("GET", "/api/users/me", token=users["B"]["tokens"][0])
    status_check("D4", "B still exists after failed deletes", "200", r, 200)
    r = call("DELETE", "/api/users/me", {"password": b_pw}, token=users["B"]["tokens"][0])
    check("D5", "DELETE /me right password (user B)", "200 + message", r, r.status == 200, note="message=" + repr(r.message))
    if r.status == 200:
        users["B"]["deleted"] = True
        r = call("GET", "/api/users/me", token=users["B"]["tokens"][0])
        status_check("D6", "token of deleted user", "401", r, 401)
        r = login(b_email, b_pw)
        status_check("D7", "login of deleted user", "401", r, 401)
        r, _, _ = register("B2", name="Bob Again", email=b_email)
        check("D8", "email is free again after deletion (re-register same address)", "201", r, r.status == 201,
              note="status=" + str(r.status) + " " + r.message)

    # C: delete while locked (token still works?) is done in cleanup()
    print("\n== summary ==", flush=True)


def run_lockout_expiry(args):
    """One throwaway user: lock it, then check it is still locked at ~14 min and free at ~15 min."""
    r, email, pw = register("C", name="Lockout Expiry")
    status_check("W0", "register throwaway user for lockout expiry", "201", r, 201)
    if "C" not in users:
        raise Abort("no user")
    seq = [login(email, new_password()).status for _ in range(5)]
    t_lock = time.time()
    check("W1", "5 wrong passwords", "401 x5", f"statuses={seq}", seq == [401] * 5, note=str(seq))
    r = login(email, pw)
    status_check("W2", "right password right after the 5th failure", "429", r, 429)
    time.sleep(14 * 60 - (time.time() - t_lock))
    r = login(email, pw)
    status_check("W3", "right password ~14 min after the 5th failure", "429 (still locked)", r, 429,
                 note=f"elapsed={time.time() - t_lock:.0f}s")
    time.sleep(max(0, 15 * 60 + 20 - (time.time() - t_lock)))
    r = login(email, pw)
    check("W4", "right password ~15 min 20 s after the 5th failure", "200 (lock expired)", r, r.status == 200,
          note=f"elapsed={time.time() - t_lock:.0f}s status={r.status}")
    if token_of(r):
        users["C"]["tokens"].append(token_of(r))


def write_outputs(out):
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, "results.md"), "w") as f:
        f.write("| ID | Check | Expected | Actual | Result | Note |\n|---|---|---|---|---|---|\n")
        for r in results:
            esc = lambda s: redact(s).replace("|", "\\|").replace("\n", " ")
            f.write(f"| {r['id']} | {esc(r['what'])} | {esc(r['expected'])} | {esc(r['actual'])[:200]} | {'PASS' if r['pass'] else 'FAIL'} | {esc(r['note'])[:400]} |\n")
    with open(os.path.join(out, "transcript.json"), "w") as f:
        f.write(redact(json.dumps({"calls": calls, "throttles": throttles, "rate_limit_log": rl_log, "users_created": registered,
                                   "transcript": transcript}, indent=1)))
    print(f"wrote {out}/results.md and transcript.json (redacted)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "out"))
    ap.add_argument("--wait-lockout", action="store_true", help="also wait 15 min and test lockout expiry")
    ap.add_argument("--keys-only", action="store_true", help="only the checks that create no users (about 15 requests)")
    ap.add_argument("--ratelimit-only", action="store_true", help="only the rate-limit test (about 1.5 minutes, no users)")
    ap.add_argument("--lockout-only", action="store_true",
                    help="only test lockout expiry with one throwaway user (takes ~16 minutes)")
    args = ap.parse_args()
    if not re.fullmatch(r"[0-9a-fA-F-]{36}", KEY):
        sys.exit("Set SIMPLEAPI_KEY to your Auth API key (uuid). It is never written to disk.")
    hide(KEY)
    started = time.time()
    try:
        (run_lockout_expiry if args.lockout_only else (lambda a: key_checks()) if args.keys_only
         else (lambda a: rate_limit_test()) if args.ratelimit_only else run)(args)
    except Abort as e:
        print("ABORTED:", e)
    finally:
        cleanup()
        # evidence that deletion worked (the user list is admin-only, so check each account directly)
        for label, u in users.items():
            if u["deleted"]:
                r = login(u["email"], u["password"])
                check("Z." + label, f"after cleanup, login as deleted user {label}", "401 (429 if a lockout is still running)", r,
                      r.status in (401, 429), note="a deleted email stays locked until its lockout expires" if r.status == 429 else "")
        undeleted = [l for l, u in users.items() if not u["deleted"]]
        print(f"users created: {registered} (cap {MAX_USERS}); not deleted: {undeleted or 'none'}")
        print(f"calls: {calls} in {time.time()-started:.0f}s; generic throttles seen: {len(throttles)}")
        write_outputs(args.out)
    fails = [r for r in results if not r["pass"]]
    print(f"{len(results)-len(fails)}/{len(results)} checks passed; failures: {[r['id'] for r in fails]}")


if __name__ == "__main__":
    main()
