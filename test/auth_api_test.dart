import 'dart:convert';

import 'package:auth_client/auth_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// All values below are made up for the tests; nothing talks to the network.
const _userJson = {
  'id': 7,
  'name': 'Test User',
  'email': 'test@example.test',
  'email_verified': false,
  'admin': false,
  'enabled': true,
  'created_at': '2026-01-01T00:00:00Z',
};
const _sessionJson = {'token': 'tok-123', 'expires_at': '2026-02-01T00:00:00Z', 'user': _userJson};

http.Response _json(int status, Object body) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

/// An AuthApi whose HTTP client answers with [reply] and records requests.
({AuthApi api, List<http.Request> seen}) _api(http.Response Function(http.Request) reply,
    {String? token}) {
  final seen = <http.Request>[];
  final client = MockClient((request) async {
    seen.add(request);
    return reply(request);
  });
  return (api: AuthApi(apiKey: 'test-key', token: token, client: client), seen: seen);
}

/// Runs [call] against an API answering [status]/[body] and returns the error.
Future<ApiException> _fails(Future<Object?> Function(AuthApi) call, int status, Object body,
    {String? token}) async {
  final t = _api((_) => _json(status, body), token: token);
  try {
    await call(t.api);
  } on ApiException catch (e) {
    return e;
  }
  throw TestFailure('expected an ApiException');
}

void main() {
  group('requests', () {
    test('login and register never send the bearer token, even when one is set', () async {
      final t = _api((_) => _json(200, _sessionJson), token: 'old-token');
      await t.api.login(email: 'a@example.test', password: 'pw-12345678');
      await t.api.register(name: 'n', email: 'a@example.test', password: 'pw-12345678');
      expect(t.seen, hasLength(2));
      for (final r in t.seen) {
        expect(r.headers.containsKey('Authorization'), isFalse, reason: r.url.path);
      }
    });

    test('a protected call sends the bearer token', () async {
      final t = _api((_) => _json(200, _userJson), token: 'tok-9');
      await t.api.me();
      expect(t.seen.single.headers['Authorization'], 'Bearer tok-9');
    });

    test('register posts the body and sends the key as a query parameter', () async {
      final t = _api((_) => _json(201, _sessionJson));
      final session = await t.api
          .register(name: 'Test User', email: 'test@example.test', password: 'pw-12345678');

      final r = t.seen.single;
      expect(r.method, 'POST');
      expect(r.url.host, 'auth.simpleapi.dev');
      expect(r.url.path, '/api/users/register');
      expect(r.url.queryParameters['apikey'], 'test-key');
      expect(r.headers.containsKey('apikey'), isFalse);
      expect(r.headers.containsKey('Authorization'), isFalse);
      expect(jsonDecode(r.body),
          {'name': 'Test User', 'email': 'test@example.test', 'password': 'pw-12345678'});
      expect(session.token, 'tok-123');
      expect(session.user.name, 'Test User');
    });

    test('login posts email and password', () async {
      final t = _api((_) => _json(200, _sessionJson));
      await t.api.login(email: 'a@example.test', password: 'secret-pass');
      expect(t.seen.single.url.path, '/api/users/login');
      expect(jsonDecode(t.seen.single.body),
          {'email': 'a@example.test', 'password': 'secret-pass'});
    });

    test('me sends the bearer token', () async {
      final t = _api((_) => _json(200, _userJson), token: 'tok-123');
      final user = await t.api.me();
      expect(t.seen.single.method, 'GET');
      expect(t.seen.single.url.path, '/api/users/me');
      expect(t.seen.single.headers['Authorization'], 'Bearer tok-123');
      expect(user.id, 7);
    });

    test('updateMe sends only the given fields', () async {
      final t = _api((_) => _json(200, _userJson), token: 'tok-123');
      await t.api.updateMe(name: 'New Name');
      expect(t.seen.single.method, 'PUT');
      expect(jsonDecode(t.seen.single.body), {'name': 'New Name'});

      await t.api.updateMe(password: 'new-password-1', currentPassword: 'old-password-1');
      expect(jsonDecode(t.seen.last.body),
          {'password': 'new-password-1', 'current_password': 'old-password-1'});
    });

    test('deleteMe sends the password in a DELETE body', () async {
      final t = _api((_) => _json(200, {'message': 'Deleted'}), token: 'tok-123');
      await t.api.deleteMe('secret-pass');
      expect(t.seen.single.method, 'DELETE');
      expect(t.seen.single.url.path, '/api/users/me');
      expect(jsonDecode(t.seen.single.body), {'password': 'secret-pass'});
    });

    test('logout sends all only when asked', () async {
      final t = _api((_) => _json(200, {'message': 'Logged out'}), token: 'tok-123');
      await t.api.logout();
      expect(t.seen.last.url.path, '/api/users/logout');
      expect(t.seen.last.body, isEmpty);

      await t.api.logout(all: true);
      expect(jsonDecode(t.seen.last.body), {'all': true});
    });

    test('forgot and reset need no token', () async {
      final t = _api((_) => _json(200, {'message': 'ok'}));
      await t.api.forgotPassword('a@example.test');
      expect(t.seen.last.url.path, '/api/users/forgot');
      expect(jsonDecode(t.seen.last.body), {'email': 'a@example.test'});

      await t.api
          .resetPassword(email: 'a@example.test', code: '123456', password: 'new-password-1');
      expect(t.seen.last.url.path, '/api/users/reset');
      expect(jsonDecode(t.seen.last.body),
          {'email': 'a@example.test', 'code': '123456', 'password': 'new-password-1'});
      expect(t.seen.last.headers.containsKey('Authorization'), isFalse);
    });

    test('email verification', () async {
      final verified = {..._userJson, 'email_verified': true};
      final t = _api(
          (r) => r.url.path.endsWith('verify')
              ? _json(200, verified)
              : _json(200, {'message': 'Code sent'}),
          token: 'tok-123');

      await t.api.sendVerificationCode();
      expect(t.seen.last.method, 'POST');
      expect(t.seen.last.url.path, '/api/users/me/email/send-code');

      final user = await t.api.verifyEmail('482915');
      expect(t.seen.last.url.path, '/api/users/me/email/verify');
      expect(jsonDecode(t.seen.last.body), {'code': '482915'});
      expect(user.emailVerified, isTrue);
    });
  });

  group('errors in plain language', () {
    test('wrong password on login', () async {
      final e = await _fails((a) => a.login(email: 'a@example.test', password: 'x'), 401,
          {'message': 'Invalid credentials'});
      expect(describeError(e), 'Invalid credentials');
      expect(e.isBadSession, isFalse);
    });

    test('lockout after too many attempts', () async {
      final e = await _fails((a) => a.login(email: 'a@example.test', password: 'x'), 429,
          {'message': 'Too many failed logins for this email.  Please try again in 15 minutes.'});
      expect(e.isRateLimited, isFalse);
      expect(describeError(e), 'Too many failed logins for this email.  Please try again in 15 minutes.');
    });

    test('bad key', () async {
      final e = await _fails((a) => a.login(email: 'a@example.test', password: 'x'), 401,
          {'message': 'Unauthorized.  Please provide a valid apikey.'});
      expect(e.isBadKey, isTrue);
      expect(describeError(e), 'The API key was not accepted.');
    });

    test('register 403 is the user cap, other 403s are not', () async {
      final cap = await _fails(
          (a) => a.register(name: 'n', email: 'e@example.test', password: 'pw-12345678'), 403,
          {'message': 'Maximum number of users (25) per key has been reached.'});
      expect(cap.isUserCapReached, isTrue);
      final other = await _fails((a) => a.updateMe(name: 'x'), 403, {'message': 'x'}, token: 't');
      expect(other.isUserCapReached, isFalse);
    });

    test('expired token is a bad session', () async {
      final e = await _fails((a) => a.me(), 401, {'message': 'Unauthenticated.'}, token: 'old');
      expect(e.isBadSession, isTrue);
      expect(describeError(e), 'Your session has ended. Please log in again.');
    });

    test('register: duplicate email, full key, validation', () async {
      Future<Object?> reg(AuthApi a) =>
          a.register(name: 'n', email: 'e@example.test', password: 'pw-12345678');
      expect(describeError(await _fails(reg, 409, {'message': 'That email is already registered.'})),
          'That email is already registered.');
      expect(describeError(await _fails(reg, 403, {'message': 'Maximum number of users (25) per key has been reached.'})),
          'Maximum number of users (25) per key has been reached.');
      expect(describeError(await _fails(reg, 422, {'message': 'The email must be a valid email address.'})),
          'The email must be a valid email address.');
    });

    test('an errors map is appended to the message', () async {
      final e = await _fails((a) => a.forgotPassword('x'), 422, {
        'message': 'Validation failed.',
        'errors': {
          'email': ['The email must be valid.']
        },
      });
      expect(describeError(e), 'Validation failed. The email must be valid.');
    });

    test('wrong current password is 403 and shows the API message', () async {
      final e = await _fails(
          (a) => a.updateMe(email: 'n@example.test', currentPassword: 'bad'), 403, {'message': 'current_password is wrong.'},
          token: 't');
      expect(describeError(e), 'current_password is wrong.');
    });

    test('bad or expired code shows the API message', () async {
      final e = await _fails((a) => a.verifyEmail('000000'), 400, {'message': 'Invalid or expired verification code.'},
          token: 't');
      expect(describeError(e), 'Invalid or expired verification code.');
    });

    test('email limits show the API message', () async {
      expect(describeError(await _fails((a) => a.sendVerificationCode(), 429, {'message': 'A code was sent a moment ago.'}, token: 't')),
          'A code was sent a moment ago.');
      expect(describeError(await _fails((a) => a.forgotPassword('a@example.test'), 429, {'message': 'Email limit reached for this key today, please try again tomorrow.'})),
          'Email limit reached for this key today, please try again tomorrow.');
      expect(describeError(await _fails((a) => a.sendVerificationCode(), 409, {'message': 'Email already verified.'}, token: 't')),
          'Email already verified.');
    });

    test('the general rate limit and a missing item use the shared wording', () async {
      final limited = await _fails((a) => a.me(), 429, {'message': 'Rate limit exceeded: 60 requests per minute.  Please try again in 31 seconds.'}, token: 't');
      expect(limited.isRateLimited, isTrue);
      expect(describeError(limited), 'Too many requests. Wait a few seconds and try again.');
      final missing = await _fails((a) => a.me(), 404, {'message': 'User not found'}, token: 't');
      expect(describeError(missing), 'Not found. It may already have been deleted.');
    });

    test('non-JSON error body still gives a message', () async {
      final client = MockClient((_) async => http.Response('<html>Bad gateway</html>', 502));
      final api = AuthApi(apiKey: 'k', client: client);
      await expectLater(
        api.login(email: 'a@example.test', password: 'x'),
        throwsA(isA<ApiException>().having((e) => describeError(e), 'plain', contains('HTTP 502'))),
      );
    });

    test('network failure names the host', () async {
      final api = AuthApi(apiKey: 'k', client: MockClient((_) async => throw http.ClientException('offline')));
      final e = await api.me().then<ApiException>((_) => throw TestFailure('no error'), onError: (Object x) => x as ApiException);
      expect(describeError(e), 'Could not reach auth.simpleapi.dev. Check your connection and try again.');
    });

    test('network failure', () async {
      final client = MockClient((_) async => throw http.ClientException('offline'));
      final api = AuthApi(apiKey: 'k', client: client);
      await expectLater(
        api.login(email: 'a@example.test', password: 'x'),
        throwsA(isA<ApiException>().having((e) => e.isNetworkError, 'network', isTrue)),
      );
    });
  });
}
