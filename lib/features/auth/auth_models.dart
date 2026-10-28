import '../../core/api/api_exception.dart';

class AuthUser {
  const AuthUser({required this.id, required this.name, required this.email});

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: json['id'] as int,
      name: json['name'] as String,
      email: json['email'] as String,
    );
  }

  final int id;
  final String name;
  final String email;
}

class BusinessSummary {
  const BusinessSummary({
    required this.id,
    required this.name,
    required this.role,
  });

  factory BusinessSummary.fromJson(Map<String, dynamic> json) {
    return BusinessSummary(
      id: json['id'] as String,
      name: json['name'] as String,
      role: json['role'] as String,
    );
  }

  final String id;
  final String name;

  /// 'owner' or 'member'.
  final String role;

  bool get isOwner => role == 'owner';
}

/// What the app knows about the signed-in user, as returned by `GET /api/v1/me`.
class Session {
  const Session({required this.user, required this.businesses});

  factory Session.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>;
    final businesses = (data['businesses'] as List<dynamic>)
        .map((b) => BusinessSummary.fromJson(b as Map<String, dynamic>))
        .toList();
    return Session(
      user: AuthUser.fromJson(data['user'] as Map<String, dynamic>),
      businesses: businesses,
    );
  }

  final AuthUser user;
  final List<BusinessSummary> businesses;

  /// MVP: a user belongs to at most one business.
  BusinessSummary? get business => businesses.isEmpty ? null : businesses.first;
}

class InvitationCode {
  const InvitationCode({required this.code, required this.expiresAt});

  final String code;
  final DateTime expiresAt;
}

/// Runs [parse], turning any malformed-JSON error into an [ApiException].
T parseResponse<T>(T Function() parse) {
  try {
    return parse();
  } on TypeError {
    throw const UnexpectedResponseException(
      'The server sent a response this app could not understand.',
    );
  } on FormatException {
    throw const UnexpectedResponseException(
      'The server sent a response this app could not understand.',
    );
  }
}
