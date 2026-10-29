// The whole SimpleApi Auth API client lives in this file.
//
// Every request goes to https://auth.simpleapi.dev/api/... and carries the
// developer's key as the `apikey` QUERY parameter (not a header). Calls that
// need a logged-in user also send `Authorization: Bearer <token>`.
// The browser may call the API directly because the API allows any origin
// (CORS), so this app needs no backend of its own.
import 'dart:convert';

import 'package:http/http.dart' as http;

const defaultBaseUrl = 'https://auth.simpleapi.dev';

/// A user as returned by the API.
class User {
  const User({
    required this.id,
    required this.name,
    required this.email,
    required this.emailVerified,
    this.admin = false,
    this.enabled = true,
    this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        email: json['email'] as String? ?? '',
        emailVerified: json['email_verified'] as bool? ?? false,
        admin: json['admin'] as bool? ?? false,
        enabled: json['enabled'] as bool? ?? true,
        createdAt: json['created_at'] as String?,
      );

  final int id;
  final String name;
  final String email;
  final bool emailVerified;
  final bool admin;
  final bool enabled;
  final String? createdAt;
}

/// What register and login return: a token plus the user it belongs to.
class Session {
  const Session({required this.token, required this.user, this.expiresAt});

  factory Session.fromJson(Map<String, dynamic> json) => Session(
        token: json['token'] as String,
        expiresAt: json['expires_at'] as String?,
        user: User.fromJson(json['user'] as Map<String, dynamic>),
      );

  final String token;
  final String? expiresAt;
  final User user;
}

/// Thrown for any non-2xx answer, and for network failures (status 0).
class ApiException implements Exception {
  ApiException(this.status, this.path, this.serverMessage);

  final int status;

  /// The route that failed, for example `/api/users/login`.
  final String path;

  /// The `message` the API sent (empty when there was none).
  final String serverMessage;

  bool get isNetworkError => status == 0;

  /// 401 caused by a missing or unknown apikey.
  bool get isBadKey =>
      status == 401 && serverMessage.toLowerCase().contains('apikey');

  /// 401 on a protected route: the token is missing, expired or logged out.
  bool get isBadSession =>
      status == 401 && !isBadKey && !path.endsWith('/users/login');

  /// A plain-language explanation for the user. The status code alone is not
  /// enough because the same code means different things on different routes
  /// (429 on login is a lockout, 429 on forgot is a daily email limit).
  String get plain {
    final detail = serverMessage.isEmpty ? '' : ' ($serverMessage)';
    if (isNetworkError) {
      return 'Could not reach auth.simpleapi.dev. Check your connection and try again.';
    }
    if (isBadKey) {
      return 'The API key was not accepted. Check the key you pasted, or get a free one at keys.simpleapi.dev.';
    }
    if (isBadSession) {
      return 'Your session has ended. Please log in again.';
    }
    final login = path.endsWith('/users/login');
    final register = path.endsWith('/users/register');
    final sendCode = path.endsWith('/email/send-code');
    final forgot = path.endsWith('/users/forgot');
    final codeCheck = path.endsWith('/users/reset') || path.endsWith('/email/verify');
    switch (status) {
      case 400 when codeCheck:
        return 'That code is wrong or has expired. A code works once, lasts 15 minutes and allows 5 wrong attempts. Request a new code if needed.$detail';
      case 401 when login:
        return 'Wrong email or password.';
      case 403 when login:
        return 'This account has been disabled.';
      case 403 when register:
        return 'This key already has the maximum of 25 users on the free tier. Delete an account or use another key.';
      case 403:
        return 'The current password is wrong.';
      case 409 when sendCode:
        return 'This email address is already verified.';
      case 409:
        return 'That email is already registered.';
      case 422:
        return serverMessage.isEmpty ? 'Some of the details are not valid.' : serverMessage;
      case 429 when login:
        return 'Too many failed log-in attempts. This email is locked for 15 minutes; try again later.$detail';
      case 429 when sendCode:
        return 'Please wait a minute before asking for another code (there is also a limit of 20 emails per day for each key).$detail';
      case 429 when forgot:
        return 'The daily limit of 20 reset and verification emails for this key has been reached. Try again tomorrow.$detail';
    }
    return serverMessage.isEmpty ? 'Something went wrong (HTTP $status).' : '$serverMessage (HTTP $status)';
  }

  @override
  String toString() => 'ApiException($status $path: $serverMessage)';
}

class AuthApi {
  AuthApi({
    required this.apiKey,
    this.token,
    http.Client? client,
    this.baseUrl = defaultBaseUrl,
  }) : _client = client ?? http.Client();

  final String apiKey;
  final String baseUrl;
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
  /// Emails a 6 digit reset code. Always answers 200 so it cannot reveal
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
  /// (all devices) when [all] is true.
  Future<String> logout({bool all = false}) async {
    final json = await _send('POST', '/api/users/logout',
        auth: true, body: all ? {'all': true} : null);
    return _message(json);
  }

  /// POST /api/users/me/email/send-code
  /// Emails a 6 digit code to verify the user's email address. One email per
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
    bool auth = false,
  }) async {
    // The key travels in the query string: ...?apikey=<key>
    final uri = Uri.parse(baseUrl).replace(path: path, queryParameters: {'apikey': apiKey});
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
      throw ApiException(0, path, '');
    }

    final decoded = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, path, _errorText(decoded));
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
