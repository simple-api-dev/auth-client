/// The whole SimpleAPI Auth API client lives in this file.
///
/// Every request goes to https://auth.simpleapi.dev/api/... and carries your
/// API key in the `apikey` query string (an `APIKEY` header also works). Calls that need a
/// logged-in user also send `Authorization: Bearer <token>`. The browser may
/// call the API directly because the API allows any origin (CORS), so this app
/// needs no backend of its own.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

const defaultHost = 'https://auth.simpleapi.dev';

/// Thrown for any non-2xx answer, and for network failures (statusCode 0).
class ApiException implements Exception {
  ApiException(this.statusCode, this.path, this.serverMessage, {this.retryAfter, this.host = defaultHost});

  final int statusCode;

  /// The route that failed, for example `/api/users/login`.
  final String path;

  /// The `message` the API sent (empty when there was none).
  final String serverMessage;

  /// The `Retry-After` header of a 429, or null when it was absent.
  final Duration? retryAfter;

  /// The server this call went to.
  final String host;

  bool get isNetworkError => statusCode == 0;

  /// The key already has the maximum number of users (403 on register).
  bool get isUserCapReached => statusCode == 403 && path.endsWith('/users/register');

  /// 401 caused by a missing or unknown apikey.
  bool get isBadKey => statusCode == 401 && serverMessage.toLowerCase().contains('apikey');

  /// The general per-IP rate limit (any route), as opposed to the login
  /// lockout or the email limits, which are 429 too. Its message starts with
  /// "Rate limit exceeded".
  bool get isRateLimited =>
      statusCode == 429 && serverMessage.toLowerCase().startsWith('rate limit');

  /// 401 on a protected route: the token is missing, expired or logged out.
  bool get isBadSession =>
      statusCode == 401 && !isBadKey && !path.endsWith('/users/login');

  @override
  String toString() => 'ApiException($statusCode $path: $serverMessage)';
}

/// The one place errors become text for the user. The wording is the same in
/// every SimpleAPI sample app.
String describeError(ApiException e) {
  final api = e.serverMessage;
  if (e.isNetworkError) {
    return 'Could not reach ${Uri.parse(e.host).host}. Check your connection and try again.';
  }
  if (e.isBadKey) return 'The API key was not accepted.';
  if (e.isBadSession) return 'Your session has ended. Please log in again.';
  if (e.isRateLimited) return 'Too many requests. Wait a few seconds and try again.';
  switch (e.statusCode) {
    case 404:
      return 'Not found. It may already have been deleted.';
    case 503:
      return 'The service is busy. Please try again shortly.';
    case 401: // a wrong email or password on login
    case 400:
    case 403:
    case 409:
    case 422:
    case 429: // the login lockout and the daily email limit say how long to wait
      if (api.isNotEmpty) return api;
  }
  return api.isEmpty ? 'Something went wrong. Please try again.' : api;
}

class AuthApi {
  AuthApi({
    required this.apiKey,
    this.token,
    http.Client? client,
    this.host = defaultHost,
  }) : _client = client ?? http.Client();

  final String apiKey;
  final String host;
  final http.Client _client;

  /// Set after register/login, sent as the Bearer token on protected calls.
  String? token;

  // ---- Public (no token) ---------------------------------------------------

  /// POST /api/users/register
  /// Creates a user and logs them in. 201 returns a Session.
  /// 409 email taken, 403 key is full (25 users), 422 validation.
  Future<Session> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final json = await _send('POST', '/api/users/register',
        body: {'name': name, 'email': email, 'password': password});
    return Session.fromJson(json);
  }

  /// POST /api/users/login
  /// Returns a Session. 401 wrong credentials; after 5 failed attempts the
  /// email is locked for 15 minutes (429).
  Future<Session> login({required String email, required String password}) async {
    final json = await _send('POST', '/api/users/login',
        body: {'email': email, 'password': password});
    return Session.fromJson(json);
  }

  /// POST /api/users/forgot
  /// Emails a 6-digit reset code. Always answers 200 so it cannot reveal
  /// whether the email is registered. Returns the API's message.
  Future<String> forgotPassword(String email) async {
    final json = await _send('POST', '/api/users/forgot', body: {'email': email});
    return _message(json);
  }

  /// POST /api/users/reset
  /// Sets a new password using the emailed code (works once, 15 minutes,
  /// 5 wrong attempts). Logs out every session. 400 means a bad/expired code.
  Future<String> resetPassword({
    required String email,
    required String code,
    required String password,
  }) async {
    final json = await _send('POST', '/api/users/reset',
        body: {'email': email, 'code': code, 'password': password});
    return _message(json);
  }

  // ---- Protected (Bearer token) -------------------------------------------

  /// GET /api/users/me
  /// The logged in user. 401 when the token is missing, invalid or expired.
  Future<User> me() async {
    final json = await _send('GET', '/api/users/me', auth: true);
    return User.fromJson(json);
  }

  /// PUT /api/users/me
  /// Send only the fields you want to change. Changing [email] or [password]
  /// requires [currentPassword] (403 if wrong). A new email must be verified
  /// again; a new password logs out every other session.
  Future<User> updateMe({
    String? name,
    String? email,
    String? password,
    String? currentPassword,
  }) async {
    final json = await _send('PUT', '/api/users/me', auth: true, body: {
      'name': ?name,
      'email': ?email,
      'password': ?password,
      'current_password': ?currentPassword,
    });
    return User.fromJson(json);
  }

  /// DELETE /api/users/me
  /// Deletes your own account. Needs the password in the body (403 if wrong).
  Future<String> deleteMe(String password) async {
    final json = await _send('DELETE', '/api/users/me',
        auth: true, body: {'password': password});
    return _message(json);
  }

  /// POST /api/users/logout
  /// Ends the session of the token you send, or every session of the user
  /// (all devices, `?all=true`) when [all] is true.
  Future<String> logout({bool all = false}) async {
    final json = await _send('POST', '/api/users/logout',
        auth: true, query: all ? {'all': 'true'} : null);
    return _message(json);
  }

  /// POST /api/users/me/email/send-code
  /// Emails a 6-digit code to verify the user's email address. One email per
  /// minute (429), 409 if already verified.
  Future<String> sendVerificationCode() async {
    final json = await _send('POST', '/api/users/me/email/send-code', auth: true);
    return _message(json);
  }

  /// POST /api/users/me/email/verify
  /// Confirms the emailed code. Returns the user with email_verified true.
  /// 400 means a bad or expired code.
  Future<User> verifyEmail(String code) async {
    final json = await _send('POST', '/api/users/me/email/verify',
        auth: true, body: {'code': code});
    return User.fromJson(json);
  }

  // ---- Plumbing ------------------------------------------------------------

  String _message(Map<String, dynamic> json) => json['message'] as String? ?? '';

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    bool auth = false,
  }) async {
    // The key travels in the query string: ...?apikey=<key>
    final uri = Uri.parse(host).replace(path: path, queryParameters: {'apikey': apiKey, ...?query});
    final request = http.Request(method, uri)..headers['Accept'] = 'application/json';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    if (auth) request.headers['Authorization'] = 'Bearer $token';

    final http.Response response;
    try {
      response = await http.Response.fromStream(await _client.send(request));
    } on http.ClientException {
      throw ApiException(0, path, '', host: host);
    }

    final decoded = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final seconds = int.tryParse(response.headers['retry-after']?.trim() ?? '');
      throw ApiException(response.statusCode, path, _errorText(decoded),
          host: host,
          retryAfter: seconds == null || seconds < 0 ? null : Duration(seconds: seconds));
    }
    return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  }

  dynamic _decode(String body) {
    if (body.isEmpty) return null;
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }

  /// Errors are `{"message": "..."}`. If a validation answer also carries an
  /// `errors` map (field -> list of problems) those are appended.
  String _errorText(dynamic decoded) {
    if (decoded is! Map) return '';
    final parts = <String>[];
    final message = decoded['message'];
    if (message is String && message.isNotEmpty) parts.add(message);
    final errors = decoded['errors'];
    if (errors is Map) {
      for (final value in errors.values) {
        if (value is List) {
          parts.addAll(value.map((e) => '$e'));
        } else if (value is String) {
          parts.add(value);
        }
      }
    }
    return parts.join(' ');
  }
}
