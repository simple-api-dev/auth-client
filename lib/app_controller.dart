import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'auth_api.dart';
import 'key_store.dart';

/// App-wide state: the saved key and the logged-in user. Screens listen to
/// it with ListenableBuilder; no state-management package is needed.
///
/// The session token is kept in memory only, so reloading the page logs out.
class AppController extends ChangeNotifier {
  AppController({required this.keyStore, this.client}) {
    apiKey = keyStore.read();
  }

  final KeyStore keyStore;
  final http.Client? client;
  AuthApi? _api;

  String? apiKey;
  User? user;

  /// A one-off message for the log-in screen (for example "session ended").
  String? notice;

  bool get hasKey => apiKey != null && apiKey!.isNotEmpty;
  bool get loggedIn => user != null;

  /// The API client for the current key. It also holds the session token.
  AuthApi get api => _api ??= AuthApi(apiKey: apiKey!, client: client);

  void saveKey(String key) {
    apiKey = key.trim();
    keyStore.write(apiKey!);
    _api = null;
    user = null;
    notice = null;
    notifyListeners();
  }

  void forgetKey() {
    keyStore.clear();
    apiKey = null;
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
