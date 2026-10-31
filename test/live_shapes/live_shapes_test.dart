// Replays REAL responses captured from https://auth.simpleapi.dev on
// 2026-10-31 (see tool/live_check/REPORT.md) through the app's AuthApi, to
// check the app copes with the exact status codes and bodies the live API
// sends. Bodies are written the way they arrive on the wire (PHP escapes `/`
// as `\/` and non-ASCII as `\uXXXX`). Emails are throwaway addresses; there
// are no keys, tokens or passwords here (the token below is a placeholder).
import 'package:auth_client/auth_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _user =
    r'{"id":3,"name":"Alice Live","email":"simpleapi-sample-apps+099e2e8586@agentmail.to",'
    r'"email_verified":false,"admin":false,"enabled":true,"created_at":"2026-10-31T20:40:37.000000Z"}';

AuthApi _api(int status, String body,
        {String? token = 'placeholder-token', Map<String, String> headers = const {}}) =>
    AuthApi(
      apiKey: 'test-key',
      token: token,
      client: MockClient((_) async =>
          http.Response(body, status, headers: {'content-type': 'application/json', ...headers})),
    );

Future<ApiException> _fail(Future<Object?> Function(AuthApi) call, int status, String body,
    {Map<String, String> headers = const {}}) async {
  try {
    await call(_api(status, body, headers: headers));
  } on ApiException catch (e) {
    return e;
  }
  fail('expected an ApiException for HTTP $status');
}

void main() {
  group('success shapes (200/201)', () {
    test('register 201 -> Session', () async {
      final s = await _api(201,
              '{"token":"placeholder-token","expires_at":"2026-11-30T20:40:37.000000Z","user":$_user}')
          .register(name: 'Alice Live', email: 'a@example.test', password: 'x' * 8);
      expect(s.token, 'placeholder-token');
      expect(s.expiresAt, '2026-11-30T20:40:37.000000Z');
      expect(s.user.id, 3);
      expect(s.user.emailVerified, isFalse);
      expect(s.user.admin, isFalse);
      expect(s.user.enabled, isTrue);
    });

    test('GET /me 200 -> User (bare user object, not wrapped)', () async {
      final u = await _api(200, _user).me();
      expect(u.name, 'Alice Live');
      expect(u.createdAt, '2026-10-31T20:40:37.000000Z');
    });

    test('a stored empty name (accounts from before the API fix) still parses', () async {
      final u = await _api(200, _user.replaceFirst('Alice Live', '')).me();
      expect(u.name, '');
    });

    test(r'unicode + escaped slash round-trip exactly as PHP encodes them', () async {
      final body = _user.replaceFirst(
          'Alice Live', r'Zoë 😀 ñ <b>x<\/b> & \"q\"');
      final u = await _api(200, body).updateMe(name: 'x');
      expect(u.name, 'Zoë 😀 ñ <b>x</b> & "q"');
    });

    test('message-only 200s', () async {
      expect(await _api(200, '{"message":"Logged out."}').logout(), 'Logged out.');
      expect(await _api(200, '{"message":"Logged out of all sessions."}').logout(all: true),
          'Logged out of all sessions.');
      expect(await _api(200, '{"message":"Account deleted."}').deleteMe('pw'), 'Account deleted.');
      expect(
          await _api(200,
                  '{"message":"If an account exists for that email, a reset code has been sent."}')
              .forgotPassword('a@example.test'),
          'If an account exists for that email, a reset code has been sent.');
      expect(
          await _api(200,
                  '{"message":"A verification code has been sent to simpleapi-sample-apps+6e994565e6@agentmail.to."}')
              .sendVerificationCode(),
          startsWith('A verification code has been sent'));
    });
  });

  group('401', () {
    const noKey =
        r'{"message":"Unauthorized.  Please provide a valid apikey. Register for a free apikey at https:\/\/keys.simpleapi.dev using product URL https:\/\/auth.simpleapi.dev."}';
    const badKey =
        r'{"message":"Unauthorized.  Invalid apikey detected [00000000-0000-0000-0000-000000000000]. Register for a free apikey at https:\/\/keys.simpleapi.dev using product URL https:\/\/auth.simpleapi.dev."}';
    const badToken = '{"message":"Invalid or expired auth token. Log in again."}';
    const noToken =
        r'{"message":"Unauthorized. Log in and send the header \"Authorization: Bearer <token>\"."}';

    test('missing / unknown apikey is a bad KEY, not a bad session', () async {
      for (final body in [noKey, badKey]) {
        final e = await _fail((a) => a.me(), 401, body);
        expect(e.isBadKey, isTrue);
        expect(e.isBadSession, isFalse);
        expect(e.plain, startsWith('The API key was not accepted'));
        final login = await _fail((a) => a.login(email: 'a@example.test', password: 'x'), 401, body);
        expect(login.isBadKey, isTrue);
      }
    });

    test('dead or missing token is a bad SESSION, not a bad key', () async {
      for (final body in [badToken, noToken]) {
        for (final call in <Future<Object?> Function(AuthApi)>[
          (a) => a.me(),
          (a) => a.updateMe(name: 'x'),
          (a) => a.logout(),
          (a) => a.deleteMe('pw'),
          (a) => a.sendVerificationCode(),
          (a) => a.verifyEmail('123456'),
        ]) {
          final e = await _fail(call, 401, body);
          expect(e.isBadKey, isFalse, reason: body);
          expect(e.isBadSession, isTrue, reason: body);
          expect(e.plain, 'Your session has ended. Please log in again.');
        }
      }
    });

    test('login 401 = wrong credentials (never "session ended")', () async {
      final e = await _fail((a) => a.login(email: 'a@example.test', password: 'x'), 401,
          '{"message":"Invalid email or password."}');
      expect(e.isBadSession, isFalse);
      expect(e.isBadKey, isFalse);
      expect(e.plain, 'Wrong email or password.');
    });
  });

  group('403', () {
    test('PUT /me wrong current_password', () async {
      final e = await _fail((a) => a.updateMe(email: 'n@example.test', currentPassword: 'x'), 403,
          '{"message":"current_password is wrong."}');
      expect(e.plain, 'The current password is wrong.');
      expect(e.isBadSession, isFalse);
    });

    test('DELETE /me wrong password', () async {
      final e = await _fail((a) => a.deleteMe('x'), 403, '{"message":"Wrong password."}');
      expect(e.plain, 'The current password is wrong.');
    });
  });

  group('404 / 405 (never produced by the app, but must not crash)', () {
    test('404 unknown route', () async {
      final e = await _fail((a) => a.me(), 404, '{"message":"Not a valid api route - not found."}');
      expect(e.plain, 'Not a valid api route - not found. (HTTP 404)');
    });

    test('empty / non-JSON error body', () async {
      final e = await _fail((a) => a.me(), 405, '');
      expect(e.plain, 'Something went wrong (HTTP 405).');
      final h = await _fail((a) => a.me(), 502, '<html>Bad gateway</html>');
      expect(h.plain, 'Something went wrong (HTTP 502).');
    });
  });

  group('409', () {
    const msg = '{"message":"That email is already registered."}';
    test('register duplicate', () async {
      final e = await _fail(
          (a) => a.register(name: 'n', email: 'a@example.test', password: 'x' * 8), 409, msg);
      expect(e.plain, 'That email is already registered.');
    });

    test('PUT /me change email to an existing one', () async {
      final e = await _fail(
          (a) => a.updateMe(email: 'a@example.test', currentPassword: 'x'), 409, msg);
      expect(e.plain, 'That email is already registered.');
    });
  });

  group('422', () {
    test('single validation message is shown as sent', () async {
      final e = await _fail(
          (a) => a.register(name: 'n', email: 'bad', password: 'x' * 8), 422,
          '{"message":"The email must be a valid email address."}');
      expect(e.plain, 'The email must be a valid email address.');
    });

    test('several problems arrive joined in ONE message string (two spaces between)', () async {
      final e = await _fail((a) => a.register(name: '', email: '', password: ''), 422,
          '{"message":"The name field is required.  The email field is required.  The password field is required."}');
      expect(e.plain, contains('The name field is required.'));
      expect(e.plain, contains('The password field is required.'));
    });

    test('password rules', () async {
      for (final m in [
        'The password must be at least 8 characters.',
        'The password may not be greater than 72 characters.',
        'The name may not be greater than 255 characters.',
      ]) {
        final e = await _fail((a) => a.updateMe(password: 'x', currentPassword: 'y'), 422,
            '{"message":"$m"}');
        expect(e.plain, m);
      }
    });

    test('PUT /me without current_password (the API answers 422, not 403)', () async {
      final e = await _fail((a) => a.updateMe(email: 'n@example.test'), 422,
          r'{"message":"The current password field is required when email \/ password is present."}');
      expect(e.plain, contains('current password field is required'));
    });
  });

  group('400 (wrong emailed codes)', () {
    test('verify email', () async {
      final e = await _fail((a) => a.verifyEmail('000000'), 400,
          '{"message":"Invalid or expired verification code."}');
      expect(e.plain, startsWith('That code is wrong or has expired.'));
      expect(e.plain, contains('Invalid or expired verification code.'));
    });

    test('reset password', () async {
      final e = await _fail(
          (a) => a.resetPassword(email: 'a@example.test', code: '000000', password: 'x' * 8),
          400,
          '{"message":"Invalid or expired reset code."}');
      expect(e.plain, startsWith('That code is wrong or has expired.'));
    });
  });

  group('429', () {
    test('login lockout (5 wrong passwords)', () async {
      final e = await _fail((a) => a.login(email: 'a@example.test', password: 'x'), 429,
          '{"message":"Too many failed logins for this email.  Please try again in a few minutes."}');
      expect(e.isBadSession, isFalse);
      expect(e.isRateLimited, isFalse);
      expect(e.retryAfter, isNull);
      expect(e.plain, startsWith('Too many failed log-in attempts.'));
      expect(e.plain, contains('15 minutes'));
    });

    test('login lockout, new text + Retry-After header', () async {
      final e = await _fail((a) => a.login(email: 'a@example.test', password: 'x'), 429,
          '{"message":"Too many failed logins for this email.  Please try again in 15 minutes."}',
          headers: {'retry-after': '725'});
      expect(e.retryAfter, const Duration(seconds: 725));
      expect(e.isRateLimited, isFalse);
      expect(e.plain, contains('locked for up to 15 minutes'));
      expect(e.plain, endsWith('Try again in about 13 minutes.'));
    });

    test('general rate limit on login is not shown as a lockout', () async {
      final e = await _fail((a) => a.login(email: 'a@example.test', password: 'x'), 429,
          '{"message":"Rate limit exceeded: 20 requests per minute.  Please try again in 31 seconds."}',
          headers: {'retry-after': '31', 'x-ratelimit-remaining': '0'});
      expect(e.isRateLimited, isTrue);
      expect(e.retryAfter, const Duration(seconds: 31));
      expect(e.plain, 'Too many requests from your network. Try again in 31 seconds.');
    });

    test('rate limit without a readable Retry-After (browser did not expose it)', () async {
      final e = await _fail((a) => a.me(), 429,
          '{"message":"Rate limit exceeded: 20 requests per minute.  Please try again in 31 seconds."}');
      expect(e.retryAfter, isNull);
      expect(e.plain, 'Too many requests from your network. Wait a moment and try again.');
    });

    test('garbage Retry-After is ignored', () async {
      final e = await _fail((a) => a.me(), 429, '{"message":"Rate limit exceeded: 20 requests per minute."}',
          headers: {'retry-after': 'Wed, 21 Oct 2026 07:28:00 GMT'});
      expect(e.retryAfter, isNull);
    });

    test('send-code one-per-minute', () async {
      final e = await _fail((a) => a.sendVerificationCode(), 429,
          '{"message":"A code was sent a moment ago.  Please wait a minute before asking for another."}');
      expect(e.plain, startsWith('Please wait a minute'));
    });

    test('a generic gateway throttle on a protected route is not mistaken for a lockout', () async {
      // The sibling Reviews API answers {"message":"Throttle Limit Exceeded"}; the Auth API was
      // never seen to send it, but the app must still show something sensible if it does.
      final e = await _fail((a) => a.me(), 429, '{"message":"Throttle Limit Exceeded"}');
      expect(e.plain, 'Throttle Limit Exceeded (HTTP 429)');
      expect(e.isBadSession, isFalse);
    });
  });

  group('checkKey() (GET /api/keys/check)', () {
    test('good key: 200 {"valid":true}', () async {
      await _api(200, '{"valid":true}').checkKey();
    });

    test('bad key, message without the key text (after the API fix)', () async {
      final e = await _fail((a) => a.checkKey(), 401,
          r'{"message":"Unauthorized.  Invalid apikey. Register for a free apikey at https:\/\/keys.simpleapi.dev using product URL https:\/\/auth.simpleapi.dev."}');
      expect(e.isBadKey, isTrue);
      expect(e.plain, startsWith('The API key was not accepted'));
    });

    test('bad key, current live message that echoes the key', () async {
      final e = await _fail((a) => a.checkKey(), 401,
          r'{"message":"Unauthorized.  Invalid apikey detected [00000000-0000-0000-0000-000000000000]. Register for a free apikey at https:\/\/keys.simpleapi.dev using product URL https:\/\/auth.simpleapi.dev."}');
      expect(e.isBadKey, isTrue);
    });

    test('a 401 from keys/check is a bad key whatever the wording', () async {
      final e = await _fail((a) => a.checkKey(), 401, '{"message":"Nope."}');
      expect(e.isBadKey, isTrue);
    });

    test('rate limited while checking', () async {
      final e = await _fail((a) => a.checkKey(), 429,
          '{"message":"Rate limit exceeded: 20 requests per minute.  Please try again in 9 seconds."}',
          headers: {'retry-after': '9'});
      expect(e.isBadKey, isFalse);
      expect(e.plain, contains('9 seconds'));
    });

    test('missing key: real 401 is rethrown as a bad key', () async {
      final e = await _fail((a) => a.checkKey(), 401,
          r'{"message":"Unauthorized.  Please provide a valid apikey. Register for a free apikey at https:\/\/keys.simpleapi.dev using product URL https:\/\/auth.simpleapi.dev."}');
      expect(e.isBadKey, isTrue);
    });
  });

  group('new live validation answers', () {
    test('malformed JSON -> 400, shown plainly, never taken for a code error or a bad key', () async {
      final e = await _fail((a) => a.updateMe(name: 'x'), 400,
          '{"message":"Malformed JSON body.  Send a valid JSON object."}');
      expect(e.isMalformedJson, isTrue);
      expect(e.isBadKey, isFalse);
      expect(e.plain, contains('malformed JSON'));
    });

    test('malformed JSON on the code routes is still malformed JSON, not "wrong code"', () async {
      final e = await _fail((a) => a.verifyEmail('123456'), 400,
          '{"message":"Malformed JSON body.  Send a valid JSON object."}');
      expect(e.plain, isNot(contains('wrong or has expired')));
    });

    test('wrong code is still a wrong code', () async {
      final e = await _fail((a) => a.verifyEmail('123456'), 400,
          '{"message":"Invalid or expired verification code."}');
      expect(e.isMalformedJson, isFalse);
      expect(e.plain, startsWith('That code is wrong or has expired'));
    });

    test('register with a@b -> 422 message is shown', () async {
      final e = await _fail((a) => a.register(name: 'X', email: 'a@b', password: 'x' * 8), 422,
          '{"message":"The email must be a valid email address."}');
      expect(e.plain, 'The email must be a valid email address.');
    });

    test('change email to a@b -> 422 message is shown', () async {
      final e = await _fail(
          (a) => a.updateMe(email: 'a@b', currentPassword: 'x' * 8), 422,
          '{"message":"The email must be a valid email address."}');
      expect(e.plain, 'The email must be a valid email address.');
    });

    test('empty name on update -> 422 message is shown', () async {
      final e = await _fail((a) => a.updateMe(name: ''), 422,
          '{"message":"The name field is required."}');
      expect(e.plain, 'The name field is required.');
    });
  });

  test('network failure -> status 0', () async {
    final api = AuthApi(
        apiKey: 'k', client: MockClient((_) async => throw http.ClientException('offline')));
    try {
      await api.me();
      fail('should throw');
    } on ApiException catch (e) {
      expect(e.isNetworkError, isTrue);
    }
  });

  test('request shape: apikey in the QUERY, Bearer header only on protected calls', () async {
    final seen = <http.Request>[];
    final api = AuthApi(
        apiKey: 'test-key',
        token: 'placeholder-token',
        client: MockClient((r) async {
          seen.add(r);
          return http.Response(_user, 200);
        }));
    await api.me();
    expect(seen.single.url.queryParameters['apikey'], 'test-key');
    expect(seen.single.headers['Authorization'], 'Bearer placeholder-token');
  });
}
