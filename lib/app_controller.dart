import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'auth_api.dart';
import 'config.dart';
import 'key_store.dart';
import 'url_opener.dart';

/// App-wide state: the key in use (the user's own, else the build key) and the logged-in user. Screens listen to
/// it with ListenableBuilder; no state-management package is needed.
///
/// The session token is kept in memory only, so reloading the page logs out.
class AppController extends ChangeNotifier {
  AppController({
    required this.keyStore,
    this.client,
    this.buildKey = configuredKey,
    UrlOpener? urlOpener,
  })  : openUrl = urlOpener ?? createUrlOpener(),
        _ownKey = _clean(keyStore.read());

  final KeyStore keyStore;
  final http.Client? client;

  /// Opens a link in a new tab (replaced in tests).
  final UrlOpener openUrl;

  /// The demo key compiled into the app ('' when there is none).
  final String buildKey;

  String _ownKey;
  AuthApi? _api;

  User? user;

  /// A one-off message for the log-in screen (for example "session ended").
  String? notice;

  static String _clean(String? key) => key?.trim() ?? '';

  /// True when the user pasted their own key (it overrides the build key).
  bool get usingOwnKey => _ownKey.isNotEmpty;

  /// The key every request uses: the user's own key, else the build key.
  String get apiKey => usingOwnKey ? _ownKey : buildKey;

  bool get hasKey => apiKey.isNotEmpty;

  /// True when requests use the shared demo key built into the site.
  bool get usingDemoKey => !usingOwnKey && buildKey.isNotEmpty;

  bool get loggedIn => user != null;

  /// The API client for the current key. It also holds the session token.
  AuthApi get api => _api ??= AuthApi(apiKey: apiKey, client: client);

  /// Use the user's own key (kept in localStorage) instead of the build key.
  void useOwnKey(String key) {
    _ownKey = _clean(key);
    keyStore.write(_ownKey);
    _keyChanged();
  }

  /// Forget the user's own key and go back to the build-time demo key.
  void useDemoKey() {
    _ownKey = '';
    keyStore.clear();
    _keyChanged();
  }

  void _keyChanged() {
    _api = null;
    user = null;
    notice = null;
    notifyListeners();
  }

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
