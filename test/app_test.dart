import 'dart:convert';

import 'package:auth_client/app_state.dart';
import 'package:auth_client/config.dart';
import 'package:auth_client/main.dart';
import 'package:auth_client/screens/ui.dart';
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
  'created_at': '2026-01-15T12:00:00Z',
  'updated_at': '2026-01-15T12:00:00Z',
};
const _session = {'token': 'tok-123', 'expires_at': '2026-02-01T00:00:00Z', 'user': _user};

http.Response _json(int status, Object body) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

/// The app wired to a mock HTTP client that records every request.
class Harness {
  Harness(
    http.Response Function(http.Request) handler, {
    String apiKey = 'test-key',
  }) {
    controller = AppState(
      apiKey: apiKey,
      urlOpener: opened.add,
      client: MockClient((request) async {
        requests.add(request);
        return handler(request);
      }),
    );
  }

  late final AppState controller;
  final requests = <http.Request>[];
  final opened = <String>[];

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

/// The login screen every SimpleAPI demo shares: same order, same widths, and no overflow at 360px.
Future<void> expectSharedLoginLayout(WidgetTester tester) async {
  final demo = find.widgetWithText(FilledButton, 'Try the demo account');
  final logIn = find.widgetWithText(FilledButton, 'Log in');
  final order = [
    demo,
    find.byType(Divider),
    find.text(demoNoticeText),
    find.widgetWithText(TextFormField, 'Email'),
    find.widgetWithText(TextFormField, 'Password'),
    logIn,
  ];
  final tops = [for (final item in order) tester.getTopLeft(item).dy];
  expect(tops, [...tops]..sort());
  expect(tester.getTopLeft(find.widgetWithText(TextButton, 'Create an account')).dy, greaterThanOrEqualTo(tops.last));

  expect(tester.getSize(demo).width, 512); // 560 wide with 24 of padding
  expect(tester.getSize(find.widgetWithText(TextFormField, 'Email')).width, 512);
  expect(tester.getSize(logIn).width, lessThan(512));

  tester.view.physicalSize = const Size(360, 800);
  await tester.pump();
  expect(tester.getSize(demo).width, 312);
}

void main() {
  // ---- Demo experience -----------------------------------------------------

  testWidgets('opens on log in with the demo button, notice and no key or settings UI', (tester) async {
    final h = Harness((_) => _json(401, {'message': 'Invalid credentials'}), apiKey: 'build-key');
    await h.pump(tester);

    expect(find.widgetWithText(FilledButton, 'Try the demo account'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Log in'), findsOneWidget);
    expect(find.text('Settings'), findsNothing);
    expect(find.textContaining('API key'), findsNothing);
    expect(find.text(demoNoticeText), findsOneWidget);
    expect(h.requests, isEmpty);

    await _submitLogin(tester);
    expect(h.requests.single.url.queryParameters['apikey'], 'build-key');
  });

  testWidgets('the login screen follows the shared login layout, with no separate demo card', (tester) async {
    await Harness((_) => _json(401, {'message': 'x'})).pump(tester);
    await tester.pumpAndSettle();
    expect(find.text('See it working'), findsNothing);
    expect(find.byType(Card), findsNothing);
    await expectSharedLoginLayout(tester);
  });

  testWidgets('Try the demo account logs in as the shared demo user in one click', (tester) async {
    final h = Harness((r) {
      if (r.url.path == '/api/users/login') {
        return _json(200, {..._session, 'user': {..._user, 'email': demoEmail}});
      }
      return _json(200, {..._user, 'email': demoEmail});
    });
    await h.pump(tester);
    await _tapText(tester, 'Try the demo account');

    final login = h.requests.firstWhere((r) => r.url.path == '/api/users/login');
    expect(jsonDecode(login.body), {'email': 'demo@simpleapi.dev', 'password': 'try-the-demo'});
    expect(login.headers.containsKey('Authorization'), isFalse);
    expect(find.text('Your account'), findsOneWidget);
  });

  testWidgets('top-level screens have a back arrow that opens simpleapi.dev', (tester) async {
    final h = Harness((_) => _json(401, {'message': 'x'}));
    await h.pump(tester);

    expect(find.byTooltip('Back to SimpleAPI'), findsOneWidget);
    await tester.tap(find.byTooltip('Back to SimpleAPI'));
    expect(h.opened, ['https://simpleapi.dev']);

    // An inner screen keeps the normal in-app back arrow.
    await _tapText(tester, 'Create an account');
    expect(find.byTooltip('Back to SimpleAPI'), findsNothing);
    expect(find.byType(BackButton), findsOneWidget);
  });

  testWidgets('the logged-in screen also has the back arrow', (tester) async {
    final h = Harness((r) => r.url.path == '/api/users/login' ? _json(200, _session) : _json(200, _user));
    await h.pump(tester);
    await _submitLogin(tester);
    expect(find.text('Your account'), findsOneWidget);
    expect(find.byTooltip('Back to SimpleAPI'), findsOneWidget);
  });

  testWidgets('app bar titles are short and leave room for the back arrow at 360px wide', (tester) async {
    // The test font (Ahem) is wider than Roboto, so a pixel measurement here would be wrong. In the real font
    // 'SimpleAPI Auth' is about 150px; the bar offers about 360 - 56 (back arrow) - 16 = 288px.
    final h = Harness((_) => _json(401, {'message': 'x'}));
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AuthClientApp(controller: h.controller));

    final bar = tester.widget<AppBar>(find.byType(AppBar));
    expect((bar.title as Text).data, 'SimpleAPI Auth');
    expect((bar.title as Text).data!.length, lessThanOrEqualTo(16));
    expect(bar.actions, isNull);
    expect(bar.leading, isNotNull);
  });

  // ---- User cap on the shared demo key ----------------------------------

  Future<void> fillRegister(WidgetTester tester) async {
    await _tapText(tester, 'Create an account');
    await _type(tester, 'Name', 'Test User');
    await _type(tester, 'Email', 'test@example.test');
    await _type(tester, 'Password', 'pw-12345678');
    await tester.tap(find.widgetWithText(FilledButton, 'Register'));
    await tester.pumpAndSettle();
  }

  testWidgets('register asks for 8 characters in helper text and has no numbered label', (tester) async {
    final h = Harness((_) => _json(201, _session));
    await h.pump(tester);
    await _tapText(tester, 'Create an account');
    expect(find.text('At least 8 characters'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Password'), findsOneWidget);
  });

  testWidgets('forgot password screen is titled Reset password', (tester) async {
    final h = Harness((_) => _json(200, {'message': 'ok'}));
    await h.pump(tester);
    await _tapText(tester, 'Forgot password?');
    expect(find.text('Reset password'), findsOneWidget);
    expect(find.textContaining('6-digit code'), findsWidgets);
  });

  testWidgets('register shows the demo notice', (tester) async {
    final h = Harness((_) => _json(201, _session));
    await h.pump(tester);
    await _tapText(tester, 'Create an account');
    expect(find.text(demoNoticeText), findsOneWidget);
  });

  testWidgets('user cap says the demo is full', (tester) async {
    final h = Harness((_) =>
        _json(403, {'message': 'Free tier limit reached: 25 users per key.'}));
    await h.pump(tester);
    await fillRegister(tester);

    expect(find.text('The demo is full. It resets every night.'), findsOneWidget);
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
    final h = Harness((_) => _json(401, {'message': 'Invalid email or password.'}));
    await h.pump(tester);
    await _submitLogin(tester, password: 'nope-nope-1');

    expect(find.text('Invalid email or password.'), findsOneWidget);
    expect(find.text('Your account'), findsNothing);
  });

  testWidgets('lockout message is explained', (tester) async {
    final h = Harness((_) => _json(429, {'message': 'Too many failed logins for this email.  Please try again in 15 minutes.'}));
    await h.pump(tester);
    await _submitLogin(tester, password: 'nope-nope-1');

    expect(find.textContaining('Please try again in 15 minutes.'), findsOneWidget);
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
    await _type(tester, 'Password', 'pw-12345678');
    await tester.tap(find.widgetWithText(FilledButton, 'Register'));
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
    await _type(tester, 'Password', 'short');
    await tester.tap(find.widgetWithText(FilledButton, 'Register'));
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

    testWidgets('the profile shows a readable date, not the raw timestamp', (tester) async {
      await start(tester);
      expect(find.textContaining('Created: 15 Jan 2026'), findsOneWidget);
      expect(find.textContaining('2026-01-15'), findsNothing);
    });

    testWidgets('a refusal from the API is shown as its message', (tester) async {
      final h = Harness((r) {
        if (r.method == 'PUT') return _json(403, {'message': 'The demo account cannot be changed.'});
        return handler(r);
      });
      await h.pump(tester);
      await _submitLogin(tester);
      await _type(tester, 'Name', 'Renamed');
      await _tapText(tester, 'Save name');
      expect(find.text('The demo account cannot be changed.'), findsOneWidget);
      expect(find.text('Your account'), findsOneWidget);
    });

    testWidgets('verify email with a code', (tester) async {
      final h = await start(tester);
      await _tapText(tester, 'Email me a code');
      expect(h.requests.last.url.path, '/api/users/me/email/send-code');

      await _type(tester, '6-digit code', '482915');
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
      expect(logout.url.queryParameters['all'], 'true');
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

  group('shared demo user is protected', () {
    final demoUser = {..._user, 'email': demoEmail};
    http.Response handler(http.Request r) {
      if (r.url.path == '/api/users/login') return _json(200, {..._session, 'user': demoUser});
      if (r.url.path == '/api/users/me' && r.method == 'GET') return _json(200, demoUser);
      return _json(500, {'message': 'must not be called: ${r.method} ${r.url.path}'});
    }

    Future<Harness> demo(WidgetTester tester) async {
      final h = Harness(handler);
      await h.pump(tester);
      await _tapText(tester, 'Try the demo account');
      h.requests.clear();
      return h;
    }

    testWidgets('account changes are not offered', (tester) async {
      await demo(tester);
      for (final text in ['Verify your email', 'Change email', 'Change password', 'Delete my account', 'Save name']) {
        expect(find.text(text), findsNothing);
      }
      expect(find.text('Your account'), findsOneWidget);
    });

    testWidgets('the profile shows the name without offering an edit', (tester) async {
      await demo(tester);
      expect(find.textContaining('Name: Test User'), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
    });

    testWidgets('the password reset flow is refused for the demo email', (tester) async {
      final h = Harness(handler);
      await h.pump(tester);
      await _tapText(tester, 'Forgot password?');
      await _type(tester, 'Email', 'Demo@SimpleAPI.dev');
      await _tapText(tester, 'Email me a code');
      await _type(tester, '6-digit code', '123456');
      await _type(tester, 'New password (8 to 72 characters)', 'new-password-1');
      await _tapText(tester, 'Set new password');
      expect(find.text(demoLockedMessage), findsNWidgets(2));
      expect(h.requests, isEmpty);
    });
  });

  test('readableDate shows the day, month and year, and nothing for a bad value', () {
    expect(readableDate(DateTime(2026, 11, 1, 12).toUtc().toIso8601String()), '1 Nov 2026');
    expect(readableDate('not a date'), isNull);
    expect(readableDate(null), isNull);
  });

  testWidgets('forgot password: send code then reset', (tester) async {
    final h = Harness((_) => _json(200, {'message': 'ok'}));
    await h.pump(tester);

    await _tapText(tester, 'Forgot password?');
    await _type(tester, 'Email', 'test@example.test');
    await _tapText(tester, 'Email me a code');
    expect(h.requests.last.url.path, '/api/users/forgot');

    await _type(tester, '6-digit code', '123456');
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
