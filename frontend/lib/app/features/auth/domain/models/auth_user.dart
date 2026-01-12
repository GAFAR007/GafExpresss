/// WHAT:
/// - AuthUser model returned by backend.
///
/// DEBUGGING:
/// - fromJson prints when parsing (safe, no secrets).

import 'package:flutter/foundation.dart';

class AuthUser {
  final String id;
  final String name;
  final String email;
  final String role;

  const AuthUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    debugPrint("AUTH: AuthUser.fromJson() called");
    return AuthUser(
      id: (json["id"] ?? "").toString(),
      name: (json["name"] ?? "").toString(),
      email: (json["email"] ?? "").toString(),
      role: (json["role"] ?? "").toString(),
    );
  }
}
