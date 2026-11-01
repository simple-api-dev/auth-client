import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'auth_api.dart';

import 'config.dart';
import 'models.dart';
import 'open_url.dart';

/// App-wide state: the build-time key and the logged-in user. Screens listen to it with ListenableBuilder; no
/// state-management package is needed.
///
/// The session token is kept in memory only, so reloading the page logs out.
class AppState extends ChangeNotifier {
  AppState({this.client, this.apiKey = configuredKey, UrlOpener? urlOpener})
    : openUrl = urlOpener ?? createUrlOpener();

  final http.Client? client;

  /// Opens a link in the same tab (replaced in tests).
  final UrlOpener openUrl;

  /// The key every request uses, from `--dart-define=SIMPLEAPI_KEY` ('' when there is none).
  final String apiKey;

  AuthApi? _api;

  User? user;

  /// A one-off message for the login screen (for example "session ended").
  String? notice;

  bool get loggedIn => user != null;

  /// True when [email] is the shared demo account. Its email, password and existence are shared by every
  /// visitor, so the app refuses to change or delete it.
  static bool isDemoEmail(String? email) => email?.trim().toLowerCase() == demoEmail;

  bool get isDemoUser => isDemoEmail(user?.email);

  /// The API client for the current key. It also holds the session token.
  AuthApi get api => _api ??= AuthApi(apiKey: apiKey, client: client);

  /// Call after a successful register or login.
  void signIn(Session session) {
    api.token = session.token;
    user = session.user;
    notice = null;
    notifyListeners();
  }

  void updateUser(User updated) {
    user = updated;
    notifyListeners();
  }

  /// Forget the token and user on this device (the API call, if any, is made
  /// by the screen first).
  void signOutLocal({String? notice}) {
    _api?.token = null;
    user = null;
    this.notice = notice;
    notifyListeners();
  }
}
