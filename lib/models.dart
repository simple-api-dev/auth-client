/// The data the Auth API returns: a user, and the session made by register and login.
library;

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
