import 'dart:convert';

import 'package:auth_client/app_controller.dart';
import 'package:auth_client/key_store.dart';
import 'package:auth_client/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// Made-up values; the HTTP client is a mock, so nothing leaves the test.
const _user = {
  'id': 7,
  'name': 'Test User',
  'email': 'test@example.test',
  'email_verified': false,
  'admin': false,
  'enabled': true,
  'created_at': '2026-01-01T00:00:00Z',
};
const _session = {'token': 'tok-123', 'expires_at': '2026-02-01T00:00:00Z', 'user': _user};

http.Response _json(int status, Object body) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

/// The app wired to a mock HTTP client that records every request.
class Harness {
  Harness(http.Response Function(http.Request) handler, {String? key = 'test-key'})
      : store = MemoryKeyStore(key) {
    controller = AppController(
      keyStore: store,
      client: MockClient((request) async {
        requests.add(request);
        return handler(request);
      }),
    );
  }

  final MemoryKeyStore store;
  late final AppController controller;
  final requests = <http.Request>[];

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AuthClientApp(controller: controller));
  }
}

Future<void> _type(WidgetTester tester, String label, String text) =>
    tester.enterText(find.widgetWithText(TextFormField, label), text);

Future<void> _tapText(WidgetTester tester, String label) async {
  final finder = find.text(label);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _submitLogin(WidgetTester tester, {String password = 'pw-12345678'}) async {
  await _type(tester, 'Email', 'test@example.test');
  await _type(tester, 'Password', password);
  await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('without a key the key screen is shown and the key is saved', (tester) async {
    final h = Harness((_) => _json(200, {}), key: null);
    await h.pump(tester);

    expect(find.text('Your SimpleApi key'), findsOneWidget);
    await _type(tester, 'API key', '  my-key  ');
    await _tapText(tester, 'Save key');

    expect(h.store.read(), 'my-key');
    expect(find.widgetWithText(FilledButton, 'Log in'), findsOneWidget);
  });

  testWidgets('login success shows the profile loaded from /me', (tester) async {
    final h = Harness((r) {
      if (r.url.path == '/api/users/login') return _json(200, _session);
      if (r.url.path == '/api/users/me') return _json(200, {..._user, 'name': 'Fresh Name'});
      return _json(404, {'message': 'no'});
    });
    await h.pump(tester);
    await _submitLogin(tester);

    expect(find.text('Your account'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Name'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Fresh Name'), findsOneWidget);
    final me = h.requests.last;
    expect(me.url.path, '/api/users/me');
    expect(me.headers['Authorization'], 'Bearer tok-123');
    expect(me.url.queryParameters['apikey'], 'test-key');
    // Unverified email: the verify section is offered.
    expect(find.text('Verify your email'), findsOneWidget);
  });

  testWidgets('wrong password shows a plain message', (tester) async {
    final h = Harness((_) => _json(401, {'message': 'Invalid credentials'}));
    await h.pump(tester);
    await _submitLogin(tester, password: 'nope-nope-1');

    expect(find.text('Wrong email or password.'), findsOneWidget);
    expect(find.text('Your account'), findsNothing);
  });

  testWidgets('lockout message is explained', (tester) async {
    final h = Harness((_) => _json(429, {'message': 'Too many attempts'}));
    await h.pump(tester);
    await _submitLogin(tester, password: 'nope-nope-1');

    expect(find.textContaining('Too many failed log-in attempts'), findsOneWidget);
  });

  testWidgets('register logs the new user in', (tester) async {
    final h = Harness((r) {
      if (r.url.path == '/api/users/register') return _json(201, _session);
      return _json(200, _user);
    });
    await h.pump(tester);

    await _tapText(tester, 'Create an account');
    await _type(tester, 'Name', 'Test User');
    await _type(tester, 'Email', 'test@example.test');
    await _type(tester, 'Password (8 to 72 characters)', 'pw-12345678');
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle();

    final register = h.requests.firstWhere((r) => r.url.path == '/api/users/register');
    expect(jsonDecode(register.body)['name'], 'Test User');
    expect(find.text('Your account'), findsOneWidget);
  });

  testWidgets('register rejects a short password before calling the API', (tester) async {
    final h = Harness((_) => _json(201, _session));
    await h.pump(tester);

    await _tapText(tester, 'Create an account');
    await _type(tester, 'Name', 'Test User');
    await _type(tester, 'Email', 'test@example.test');
    await _type(tester, 'Password (8 to 72 characters)', 'short');
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle();

    expect(find.text('At least 8 characters'), findsOneWidget);
    expect(h.requests, isEmpty);
  });

  group('logged in', () {
    http.Response handler(http.Request r) {
      switch ('${r.method} ${r.url.path}') {
        case 'POST /api/users/login':
          return _json(200, _session);
        case 'GET /api/users/me':
          return _json(200, _user);
        case 'PUT /api/users/me':
          final sent = jsonDecode(r.body) as Map<String, dynamic>;
          return _json(200, {..._user, 'name': sent['name'] ?? _user['name']});
        case 'POST /api/users/me/email/send-code':
          return _json(200, {'message': 'Code sent'});
        case 'POST /api/users/me/email/verify':
          return _json(200, {..._user, 'email_verified': true});
        case 'POST /api/users/logout':
        case 'DELETE /api/users/me':
          return _json(200, {'message': 'ok'});
      }
      return _json(404, {'message': 'unexpected ${r.method} ${r.url.path}'});
    }

    Future<Harness> start(WidgetTester tester) async {
      final h = Harness(handler);
      await h.pump(tester);
      await _submitLogin(tester);
      return h;
    }

    testWidgets('edit name', (tester) async {
      final h = await start(tester);
      await _type(tester, 'Name', 'Renamed');
      await _tapText(tester, 'Save name');

      final put = h.requests.last;
      expect(put.method, 'PUT');
      expect(jsonDecode(put.body), {'name': 'Renamed'});
      expect(find.text('Name saved.'), findsOneWidget);
    });

    testWidgets('verify email with a code', (tester) async {
      final h = await start(tester);
      await _tapText(tester, 'Email me a code');
      expect(h.requests.last.url.path, '/api/users/me/email/send-code');

      await _type(tester, 'Code from the email', '482915');
      await _tapText(tester, 'Verify');
      expect(jsonDecode(h.requests.last.body), {'code': '482915'});
      // The verify section disappears once the email is verified.
      expect(find.text('Verify your email'), findsNothing);
    });

    testWidgets('log out all devices', (tester) async {
      final h = await start(tester);
      await _tapText(tester, 'Log out all devices');

      final logout = h.requests.last;
      expect(logout.url.path, '/api/users/logout');
      expect(jsonDecode(logout.body), {'all': true});
      expect(find.text('Your account'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Log in'), findsOneWidget);
    });

    testWidgets('delete account asks for confirmation', (tester) async {
      final h = await start(tester);
      // Two fields are labelled Password further down; the delete one is last.
      await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'pw-12345678');
      await _tapText(tester, 'Delete my account');
      expect(find.text('Delete account?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();

      final del = h.requests.last;
      expect(del.method, 'DELETE');
      expect(jsonDecode(del.body), {'password': 'pw-12345678'});
      expect(find.text('Your account was deleted.'), findsOneWidget);
    });

    testWidgets('an expired token sends the user back to log in', (tester) async {
      final h = Harness((r) {
        if (r.url.path == '/api/users/login') return _json(200, _session);
        return _json(401, {'message': 'Unauthenticated.'});
      });
      await h.pump(tester);
      await _submitLogin(tester);

      expect(find.widgetWithText(FilledButton, 'Log in'), findsOneWidget);
      expect(find.textContaining('session has ended'), findsOneWidget);
    });
  });

  testWidgets('forgot password: send code then reset', (tester) async {
    final h = Harness((_) => _json(200, {'message': 'ok'}));
    await h.pump(tester);

    await _tapText(tester, 'Forgot password?');
    await _type(tester, 'Email', 'test@example.test');
    await _tapText(tester, 'Send code');
    expect(h.requests.last.url.path, '/api/users/forgot');

    await _type(tester, 'Code from the email', '123456');
    await _type(tester, 'New password (8 to 72 characters)', 'new-password-1');
    await _tapText(tester, 'Set new password');
    expect(h.requests.last.url.path, '/api/users/reset');
    expect(jsonDecode(h.requests.last.body), {
      'email': 'test@example.test',
      'code': '123456',
      'password': 'new-password-1',
    });
    expect(find.textContaining('Password updated'), findsOneWidget);
  });
}
