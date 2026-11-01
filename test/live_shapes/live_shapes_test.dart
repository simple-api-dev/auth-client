// Replays the Auth API's responses through the app's AuthApi, to check the
// app copes with the exact status codes and bodies the API sends. Bodies are
// written the way they arrive on the wire (PHP escapes `/`
// as `\/` and non-ASCII as `\uXXXX`). Emails are throwaway addresses; there
// are no keys, tokens or passwords here (the token below is a placeholder).
import 'package:auth_client/auth_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _user =
    r'{"id":3,"name":"Alice Live","email":"simpleapi-sample-apps+099e2e8586@agentmail.to",'
    r'"email_verified":false,"admin":false,"enabled":true,'
    r'"created_at":"2026-10-31T20:40:37Z","updated_at":"2026-10-31T20:41:02Z"}';

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
              '{"token":"placeholder-token","expires_at":"2026-11-30T20:40:37Z","user":$_user}')
          .register(name: 'Alice Live', email: 'a@example.test', password: 'x' * 8);
      expect(s.token, 'placeholder-token');
      expect(s.expiresAt, '2026-11-30T20:40:37Z');
      expect(s.user.id, 3);
      expect(s.user.emailVerified, isFalse);
      expect(s.user.admin, isFalse);
      expect(s.user.enabled, isTrue);
    });

    test('GET /me 200 -> User (bare user object, not wrapped)', () async {
      final u = await _api(200, _user).me();
      expect(u.name, 'Alice Live');
      expect(u.createdAt, '2026-10-31T20:40:37Z');
      expect(u.updatedAt, '2026-10-31T20:41:02Z');
    });

    test('an empty name still parses', () async {
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
    const badKey =
        r'{"message":"Unauthorized. Please provide a valid apikey. Get a free key at https:\/\/keys.simpleapi.dev\/?product=auth"}';
    const badToken = '{"message":"Invalid or expired auth token. Log in again."}';
    const noToken =
        r'{"message":"Unauthorized. Log in and send the header \"Authorization: Bearer <token>\"."}';

    test('missing / unknown apikey is a bad KEY, not a bad session', () async {
      final e = await _fail((a) => a.me(), 401, badKey);
      expect(e.isBadKey, isTrue);
      expect(e.isBadSession, isFalse);
      expect(describeError(e), startsWith('The API key was not accepted'));
      final login = await _fail((a) => a.login(email: 'a@example.test', password: 'x'), 401, badKey);
      expect(login.isBadKey, isTrue);
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
          expect(describeError(e), 'Your session has ended. Please log in again.');
        }
      }
    });

    test('login 401 = wrong credentials or a disabled account (never "session ended")', () async {
      final e = await _fail((a) => a.login(email: 'a@example.test', password: 'x'), 401,
          '{"message":"Invalid email or password."}');
      expect(e.isBadSession, isFalse);
      expect(e.isBadKey, isFalse);
      expect(describeError(e), 'Invalid email or password.');
    });
  });

  group('403', () {
    test('PUT /me wrong current_password', () async {
      final e = await _fail((a) => a.updateMe(email: 'n@example.test', currentPassword: 'x'), 403,
          '{"message":"current_password is wrong."}');
      expect(describeError(e), 'current_password is wrong.');
      expect(e.isBadSession, isFalse);
    });

    test('DELETE /me wrong password', () async {
      final e = await _fail((a) => a.deleteMe('x'), 403, '{"message":"Wrong password."}');
      expect(describeError(e), 'Wrong password.');
    });
  });

  group('500 / 503', () {
    test('keys service down', () async {
      final e = await _fail((a) => a.me(), 503, '{"message":"Key service unavailable. Please try again shortly."}');
      expect(e.isBadKey, isFalse);
      expect(e.isBadSession, isFalse);
      expect(describeError(e), 'The service is busy. Please try again shortly.');
    });

    test('server error', () async {
      final e = await _fail((a) => a.me(), 500, '{"message":"Something went wrong. Please try again."}');
      expect(describeError(e), 'Something went wrong. Please try again. (HTTP 500)');
    });
  });

  group('404 / 405 (never produced by the app, but must not crash)', () {
    test('404 unknown route', () async {
      final e = await _fail((a) => a.me(), 404, '{"message":"Not a valid api route - not found."}');
      expect(describeError(e), 'Not found. It may already have been deleted.');
    });

    test('empty / non-JSON error body', () async {
      final e = await _fail((a) => a.me(), 405, '');
      expect(describeError(e), 'Something went wrong (HTTP 405).');
      final h = await _fail((a) => a.me(), 502, '<html>Bad gateway</html>');
      expect(describeError(h), 'Something went wrong (HTTP 502).');
    });
  });

  group('409', () {
    const msg = '{"message":"That email is already registered."}';
    test('register duplicate', () async {
      final e = await _fail(
          (a) => a.register(name: 'n', email: 'a@example.test', password: 'x' * 8), 409, msg);
      expect(describeError(e), 'That email is already registered.');
    });

    test('PUT /me change email to an existing one', () async {
      final e = await _fail(
          (a) => a.updateMe(email: 'a@example.test', currentPassword: 'x'), 409, msg);
      expect(describeError(e), 'That email is already registered.');
    });
  });

  group('422', () {
    test('single validation message is shown as sent', () async {
      final e = await _fail(
          (a) => a.register(name: 'n', email: 'bad', password: 'x' * 8), 422,
          '{"message":"The email must be a valid email address."}');
      expect(describeError(e), 'The email must be a valid email address.');
    });

    test('several problems arrive joined in ONE message string (two spaces between)', () async {
      final e = await _fail((a) => a.register(name: '', email: '', password: ''), 422,
          '{"message":"The name field is required.  The email field is required.  The password field is required."}');
      expect(describeError(e), contains('The name field is required.'));
      expect(describeError(e), contains('The password field is required.'));
    });

    test('password rules', () async {
      for (final m in [
        'The password must be at least 8 characters.',
        'The password may not be greater than 72 characters.',
        'The name may not be greater than 255 characters.',
      ]) {
        final e = await _fail((a) => a.updateMe(password: 'x', currentPassword: 'y'), 422,
            '{"message":"$m"}');
        expect(describeError(e), m);
      }
    });

    test('PUT /me without current_password (the API answers 422, not 403)', () async {
      final e = await _fail((a) => a.updateMe(email: 'n@example.test'), 422,
          '{"message":"current_password is required to change the email or password."}');
      expect(describeError(e), contains('current_password is required'));
    });
  });

  group('400 (wrong emailed codes)', () {
    test('verify email', () async {
      final e = await _fail((a) => a.verifyEmail('000000'), 400,
          '{"message":"Invalid or expired verification code."}');
      expect(describeError(e), 'Invalid or expired verification code.');
    });

    test('reset password', () async {
      final e = await _fail(
          (a) => a.resetPassword(email: 'a@example.test', code: '000000', password: 'x' * 8),
          400,
          '{"message":"Invalid or expired reset code."}');
      expect(describeError(e), 'Invalid or expired reset code.');
    });
  });

  group('429', () {
    test('login lockout (5 wrong passwords)', () async {
      final e = await _fail((a) => a.login(email: 'a@example.test', password: 'x'), 429,
          '{"message":"Too many failed logins for this email.  Please try again in a few minutes."}');
      expect(e.isBadSession, isFalse);
      expect(e.isRateLimited, isFalse);
      expect(e.retryAfter, isNull);
      expect(describeError(e), 'Too many failed logins for this email.  Please try again in a few minutes.');
    });

    test('login lockout, new text + Retry-After header', () async {
      final e = await _fail((a) => a.login(email: 'a@example.test', password: 'x'), 429,
          '{"message":"Too many failed logins for this email.  Please try again in 15 minutes."}',
          headers: {'retry-after': '725'});
      expect(e.retryAfter, const Duration(seconds: 725));
      expect(e.isRateLimited, isFalse);
      expect(describeError(e), 'Too many failed logins for this email.  Please try again in 15 minutes.');
    });

    test('general rate limit on login is not shown as a lockout', () async {
      final e = await _fail((a) => a.login(email: 'a@example.test', password: 'x'), 429,
          '{"message":"Rate limit exceeded: 60 requests per minute.  Please try again in 31 seconds."}',
          headers: {'retry-after': '31', 'x-ratelimit-remaining': '0'});
      expect(e.isRateLimited, isTrue);
      expect(e.retryAfter, const Duration(seconds: 31));
      expect(describeError(e), 'Too many requests. Wait a few seconds and try again.');
    });

    test('rate limit without a readable Retry-After (browser did not expose it)', () async {
      final e = await _fail((a) => a.me(), 429,
          '{"message":"Rate limit exceeded: 60 requests per minute.  Please try again in 31 seconds."}');
      expect(e.retryAfter, isNull);
      expect(describeError(e), 'Too many requests. Wait a few seconds and try again.');
    });

    test('garbage Retry-After is ignored', () async {
      final e = await _fail((a) => a.me(), 429, '{"message":"Rate limit exceeded: 60 requests per minute."}',
          headers: {'retry-after': 'Wed, 21 Oct 2026 07:28:00 GMT'});
      expect(e.retryAfter, isNull);
    });

    test('send-code one-per-minute', () async {
      final e = await _fail((a) => a.sendVerificationCode(), 429,
          '{"message":"A code was sent a moment ago.  Please wait a minute before asking for another."}');
      expect(describeError(e), 'A code was sent a moment ago.  Please wait a minute before asking for another.');
    });

    test('a generic gateway throttle on a protected route is not mistaken for a lockout', () async {
      // The sibling Reviews API answers {"message":"Throttle Limit Exceeded"}; the Auth API was
      // never seen to send it, but the app must still show something sensible if it does.
      final e = await _fail((a) => a.me(), 429, '{"message":"Throttle Limit Exceeded"}');
      expect(describeError(e), 'Throttle Limit Exceeded');
      expect(e.isBadSession, isFalse);
    });
  });

  group('new live validation answers', () {
    test('malformed JSON -> 400, shown plainly, never taken for a code error or a bad key', () async {
      final e = await _fail((a) => a.updateMe(name: 'x'), 400,
          '{"message":"Malformed JSON body.  Send a valid JSON object."}');
      expect(e.isBadKey, isFalse);
      expect(describeError(e), 'Malformed JSON body.  Send a valid JSON object.');
    });

    test('malformed JSON on the code routes is still malformed JSON, not "wrong code"', () async {
      final e = await _fail((a) => a.verifyEmail('123456'), 400,
          '{"message":"Malformed JSON body.  Send a valid JSON object."}');
      expect(describeError(e), 'Malformed JSON body.  Send a valid JSON object.');
    });

    test('wrong code is still a wrong code', () async {
      final e = await _fail((a) => a.verifyEmail('123456'), 400,
          '{"message":"Invalid or expired verification code."}');
      expect(describeError(e), 'Invalid or expired verification code.');
    });

    test('register with a@b -> 422 message is shown', () async {
      final e = await _fail((a) => a.register(name: 'X', email: 'a@b', password: 'x' * 8), 422,
          '{"message":"The email must be a valid email address."}');
      expect(describeError(e), 'The email must be a valid email address.');
    });

    test('change email to a@b -> 422 message is shown', () async {
      final e = await _fail(
          (a) => a.updateMe(email: 'a@b', currentPassword: 'x' * 8), 422,
          '{"message":"The email must be a valid email address."}');
      expect(describeError(e), 'The email must be a valid email address.');
    });

    test('empty name on update -> 422 message is shown', () async {
      final e = await _fail((a) => a.updateMe(name: ''), 422,
          '{"message":"The name field is required."}');
      expect(describeError(e), 'The name field is required.');
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
