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
      expect(e.plain, 'Wrong email or password.');
      expect(e.isBadSession, isFalse);
    });

    test('lockout after too many attempts', () async {
      final e = await _fails((a) => a.login(email: 'a@example.test', password: 'x'), 429,
          {'message': 'Try again later'});
      expect(e.plain, contains('locked for 15 minutes'));
    });

    test('bad key', () async {
      final e = await _fails((a) => a.login(email: 'a@example.test', password: 'x'), 401,
          {'message': 'Unauthorized.  Please provide a valid apikey.'});
      expect(e.isBadKey, isTrue);
      expect(e.plain, contains('API key was not accepted'));
    });

    test('expired token is a bad session', () async {
      final e = await _fails((a) => a.me(), 401, {'message': 'Unauthenticated.'}, token: 'old');
      expect(e.isBadSession, isTrue);
      expect(e.plain, contains('log in again'));
    });

    test('register: duplicate email, full key, validation', () async {
      Future<Object?> reg(AuthApi a) =>
          a.register(name: 'n', email: 'e@example.test', password: 'pw-12345678');
      expect((await _fails(reg, 409, {'message': 'taken'})).plain,
          'That email is already registered.');
      expect((await _fails(reg, 403, {'message': 'limit'})).plain, contains('25 users'));
      expect((await _fails(reg, 422, {'message': 'The email must be a valid email address.'})).plain,
          'The email must be a valid email address.');
    });

    test('an errors map is appended to the message', () async {
      final e = await _fails((a) => a.forgotPassword('x'), 422, {
        'message': 'Validation failed.',
        'errors': {
          'email': ['The email must be valid.']
        },
      });
      expect(e.plain, 'Validation failed. The email must be valid.');
    });

    test('wrong current password is 403', () async {
      final e = await _fails(
          (a) => a.updateMe(email: 'n@example.test', currentPassword: 'bad'), 403, {'message': 'x'},
          token: 't');
      expect(e.plain, 'The current password is wrong.');
    });

    test('bad or expired code', () async {
      final e = await _fails((a) => a.verifyEmail('000000'), 400, {'message': 'Invalid or expired code'},
          token: 't');
      expect(e.plain, contains('wrong or has expired'));
    });

    test('email limits', () async {
      expect((await _fails((a) => a.sendVerificationCode(), 429, {'message': 'slow'}, token: 't')).plain,
          contains('wait a minute'));
      expect((await _fails((a) => a.forgotPassword('a@example.test'), 429, {'message': 'limit'})).plain,
          contains('daily limit'));
      expect((await _fails((a) => a.sendVerificationCode(), 409, {'message': 'x'}, token: 't')).plain,
          contains('already verified'));
    });

    test('non-JSON error body still gives a message', () async {
      final client = MockClient((_) async => http.Response('<html>Bad gateway</html>', 502));
      final api = AuthApi(apiKey: 'k', client: client);
      await expectLater(
        api.login(email: 'a@example.test', password: 'x'),
        throwsA(isA<ApiException>().having((e) => e.plain, 'plain', contains('HTTP 502'))),
      );
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
